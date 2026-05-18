# 20260518_123902_hand_drawing_phase4_minimap_preview_thumbnail_record

## 记录范围

- 记录内容：
  1. 为 minimap snapshot / provider / renderer 链补齐 handDrawing 独立节点类型与几何输出。
  2. 修正 `BoardGeometryPreviewBuilder` 继续把 handDrawing 写成 `image` 的问题，让 `BoardPreviewSeed` 与 minimap 语义一致。
  3. 为 `BoardThumbnailRenderer` 拆出 handDrawing 专用绘制分支，并把 poster-backed 预览图的公共几何绘制逻辑抽出来。
  4. 提取共享纸面外观配置，统一 iOS / macOS viewport 与 thumbnail 的 handDrawing 纸面样式来源。
  5. 补阶段 4 的稳定测试，并验证空白 handDrawing 的持久化缩略图仍然可见。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_123902`
- 参考依据：
  - `git status --short`
  - `git diff --stat`
  - `git diff -- MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - 当前新增文件内容：
    - `MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingPreviewAppearance.swift`
    - `MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests.swift`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingPreviewAppearance.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `M MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `M MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `M MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingPreviewAppearance.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests.swift`
- `git diff --stat` 摘要：
  - 已跟踪文件修改：8 个
  - 新增未跟踪文件：2 个
  - 主要改动集中在 `BoardThumbnailRenderer.swift`
- 本记录不包含：
  - 阶段 5 的 iOS 全屏手绘编辑器与入口编排
  - git commit / push

## 修改一：minimap 链路为 handDrawing 建立独立节点类型与 provider

### 修改前

- `CanvasMiniMapNodeKind` 没有 `handDrawing`。
- `CanvasMiniMapRenderer` 只注册 `image` / `text` provider。
- handDrawing 在 minimap 链路里没有独立节点生产入口，也不会吃到旋转预览态的临时几何。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift
// 函数名: CanvasMiniMapNodeKind
// 功能说明: 修改前 minimap node kind 没有 handDrawing，链路里无法显式区分手绘节点。
enum CanvasMiniMapNodeKind {
    case image
    case text
    case sticker
    case shape
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: 修改前 minimap renderer 只注册 image/text provider，handDrawing 不会进入统一节点聚合链。
init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
    self.nodeProviders = nodeProviders ?? [
        CanvasMiniMapImageNodeProvider(),
        CanvasMiniMapTextNodeProvider()
    ]
}
```

### 修改后

- `CanvasMiniMapNodeKind` 新增 `.handDrawing`。
- 新增 `CanvasMiniMapHandDrawingNodeProvider`。
- 新增 `effectiveMiniMapBoardItem(...)`，让 handDrawing 在 minimap 中也能复用旋转预览态几何，而不是只看已提交尺寸。
- `CanvasMiniMapRenderer` 现在把 handDrawing provider 纳入统一 `nodeProviders` 队列。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapSnapshot.swift
// 函数名: CanvasMiniMapNodeKind
// 功能说明: 修改后 minimap snapshot 可以显式携带 handDrawing 节点类型。
enum CanvasMiniMapNodeKind {
    case image
    case handDrawing
    case text
    case sticker
    case shape
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: effectiveMiniMapBoardItem(from:rotationPreviewState:) / CanvasMiniMapHandDrawingNodeProvider.makeNodes(context:)
// 功能说明: 修改后 minimap 会为 handDrawing 生成独立节点，并在旋转预览期间读取临时几何。
private func effectiveMiniMapBoardItem(
    from item: CanvasBoardItem,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasBoardItem {
    guard
        let rotationPreviewState,
        let previewGeometry = rotationPreviewState.geometry(for: item.id)
    else {
        return item
    }

    return item.applyingGeometry(previewGeometry) ?? item
}

struct CanvasMiniMapHandDrawingNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
            guard let item = boardItem.handDrawingItem else {
                return nil
            }

            let effectiveItem = effectiveMiniMapBoardItem(
                from: .handDrawing(item),
                rotationPreviewState: context.rotationPreviewState
            ).handDrawingItem ?? item

            return CanvasMiniMapNode(
                id: effectiveItem.id,
                kind: .handDrawing,
                worldQuad: effectiveItem.worldQuad,
                zIndex: effectiveItem.zIndex,
                isPreviewActive: context.rotationPreviewState?.geometry(
                    for: effectiveItem.id
                ) != nil
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: 修改后 renderer 会把 handDrawing provider 纳入统一 minimap 节点聚合链。
init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
    self.nodeProviders = nodeProviders ?? [
        CanvasMiniMapImageNodeProvider(),
        CanvasMiniMapHandDrawingNodeProvider(),
        CanvasMiniMapTextNodeProvider()
    ]
}
```

## 修改二：BoardPreviewSeed 不再把 handDrawing 伪装成 image

### 修改前

- `BoardGeometryPreviewBuilder.makeNode(from:documentOrder:)` 在 `.handDrawing` 分支里仍然写 `kind: .image`。
- `describeBoardPreviewNodeKind(_:)` 也没有 `handDrawing` 分支。
- 这会让 board list geometry seed 与 minimap snapshot 的节点语义继续分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:) / describeBoardPreviewNodeKind(_:)
// 功能说明: 修改前 handDrawing record 进入 seed 时仍被标成 image，日志层也无法打印 handDrawing 类型。
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

private func describeBoardPreviewNodeKind(_ kind: CanvasMiniMapNodeKind) -> String {
    switch kind {
    case .image:
        return "image"
    case .text:
        return "text"
    case .sticker:
        return "sticker"
    case .shape:
        return "shape"
    }
}
```

### 修改后

- `BoardGeometryPreviewBuilder` 现在把 handDrawing 写成真正的 `.handDrawing`。
- 预览日志与 seed 中的节点类型保持一致，避免 board list / minimap / persisted thumbnail replay 对同一 item 产生不同解释。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:) / describeBoardPreviewNodeKind(_:)
// 功能说明: 修改后 BoardPreviewSeed 会保留 handDrawing 节点语义，不再把手绘块降格为 image。
case let .handDrawing(handDrawingRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: handDrawingRecord.id,
        kind: .handDrawing,
        center: handDrawingRecord.center,
        size: handDrawingRecord.size,
        zIndex: handDrawingRecord.zIndex,
        rotationRadians: handDrawingRecord.rotationRadians
    )

private func describeBoardPreviewNodeKind(_ kind: CanvasMiniMapNodeKind) -> String {
    switch kind {
    case .image:
        return "image"
    case .handDrawing:
        return "handDrawing"
    case .text:
        return "text"
    case .sticker:
        return "sticker"
    case .shape:
        return "shape"
    }
}
```

## 修改三：BoardThumbnailRenderer 为 handDrawing 拆独立绘制路径，并抽公共 poster 几何逻辑

### 修改前

- render loop 在 `.handDrawing` 分支里先取 `previewImageRecord`，然后直接走 `drawLoadedImage(...)`。
- `drawLoadedImage(...)` 只认识图片语义：裁剪、旋转、贴图，没有纸面填充和边框。
- `logImageDraw(...)` / `logImageRenderedRegion(...)` / `logNodeRegionSamples(...)` 也都是 image 语义。
- 结果是 handDrawing 在 board list / persisted thumbnail 链路里只是“另一张图片”，空白手绘块的纸面外观不会被画出来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:)
// 功能说明: 修改前 handDrawing 在渲染循环里仍然退回 previewImageRecord，再复用 drawLoadedImage(...)。
case let .handDrawing(handDrawingItemRecord):
    let previewImageRecord = handDrawingItemRecord.previewImageRecord
    let image = try imageProvider(
        previewImageRecord,
        geometry,
        itemRecords
    )
    try cancellationCheck()
    drawLoadedImage(
        image,
        for: previewImageRecord,
        geometry: geometry,
        in: context,
        traceContext: traceContext,
        documentOrder: traceContext.documentOrderByID[
            handDrawingItemRecord.id
        ],
        renderOrder: renderOrder
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawLoadedImage(_:for:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改前 thumbnail 只有一条 poster 贴图路径，逻辑只覆盖图片裁剪/旋转/绘制，没有 handDrawing 纸面样式。
private func drawLoadedImage(
    _ image: CGImage,
    for itemRecord: BoardImageItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext: BoardThumbnailTraceContext,
    documentOrder: Int?,
    renderOrder: Int
) {
    let visibleSize = itemRecord.size.cgSize
    guard visibleSize.width > 0, visibleSize.height > 0 else {
        return
    }

    let cropRect = itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage
    let cropCGRect = cropRect.cgRect
    guard cropCGRect.width > 0, cropCGRect.height > 0 else {
        return
    }

    // ... 继续计算 mappedVisibleSize / fullImageRect / rotationRadians
    // ... 然后直接 clip + draw(image)
}
```

### 修改后

- 新增 `PosterBackedThumbnailLayout`，把 poster-backed 预览图共有的 `mappedCenter / visibleRect / fullImageRect / rotation` 计算抽出来。
- render loop 里 image 走 `drawImageItem(...)`，handDrawing 走 `drawHandDrawingItem(...)`。
- `drawHandDrawingItem(...)` 会先画纸面填充、再贴预览、最后补边框，因此空白手绘块在缩略图中不再透明消失。
- 新 trace 函数 `logPosterBackedDraw(...)` / `logPosterBackedRenderedRegion(...)` 会带上 `kind`，`logNodeRegionSamples(...)` 也会采样 `.handDrawing` 节点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: PosterBackedThumbnailLayout / renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:traceContext:imageProvider:)
// 功能说明: 修改后 thumbnail 渲染循环按 image / text / handDrawing 三类分流，handDrawing 不再退回“假图片”分支。
private struct PosterBackedThumbnailLayout {
    let mappedCenter: CGPoint
    let visibleRect: CGRect
    let fullImageRect: CGRect
    let rotationRadians: CGFloat
    let previewVisibleRect: CGRect
    let previewFullImageRect: CGRect
}

for (renderOrder, itemRecord) in orderedItemRecords(from: itemRecords)
    .enumerated()
{
    try cancellationCheck()
    switch itemRecord {
    case let .image(imageItemRecord):
        let image = try imageProvider(
            imageItemRecord,
            geometry,
            itemRecords
        )
        try cancellationCheck()
        drawImageItem(
            image,
            for: imageItemRecord,
            geometry: geometry,
            in: context,
            traceContext: traceContext,
            documentOrder: traceContext.documentOrderByID[imageItemRecord.id],
            renderOrder: renderOrder
        )
    case let .text(textItemRecord):
        drawTextItem(
            textItemRecord,
            geometry: geometry,
            in: context,
            traceContext: traceContext,
            documentOrder: traceContext.documentOrderByID[textItemRecord.id],
            renderOrder: renderOrder
        )
    case let .handDrawing(handDrawingItemRecord):
        let previewImageRecord = handDrawingItemRecord.previewImageRecord
        let image = try imageProvider(
            previewImageRecord,
            geometry,
            itemRecords
        )
        try cancellationCheck()
        drawHandDrawingItem(
            image,
            for: handDrawingItemRecord,
            geometry: geometry,
            in: context,
            traceContext: traceContext,
            documentOrder: traceContext.documentOrderByID[handDrawingItemRecord.id],
            renderOrder: renderOrder
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawHandDrawingItem(_:for:geometry:in:traceContext:documentOrder:renderOrder:) / makePosterBackedLayout(center:size:rotationRadians:cropCGRect:geometry:) / drawPosterBackedImage(_:layout:in:clipPath:)
// 功能说明: 修改后 handDrawing 缩略图会显式绘制纸面填充和边框，共享 poster 几何计算只保留一份。
private func drawHandDrawingItem(
    _ image: CGImage,
    for itemRecord: BoardHandDrawingItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext: BoardThumbnailTraceContext,
    documentOrder: Int?,
    renderOrder: Int
) {
    let cropCGRect = CanvasImageCropRect.fullImage.cgRect
    guard
        let layout = makePosterBackedLayout(
            center: itemRecord.center,
            size: itemRecord.size,
            rotationRadians: itemRecord.rotationRadians,
            cropCGRect: cropCGRect,
            geometry: geometry
        )
    else {
        return
    }

    let paperPath = handDrawingPaperPath(for: layout.visibleRect)
    drawHandDrawingPaperFill(
        layout: layout,
        paperPath: paperPath,
        in: context
    )
    drawPosterBackedImage(
        image,
        layout: layout,
        in: context,
        clipPath: paperPath
    )
    drawHandDrawingPaperBorder(
        layout: layout,
        paperPath: paperPath,
        isEmpty: itemRecord.isEmpty,
        in: context
    )
}

private func makePosterBackedLayout(
    center: BoardPointRecord,
    size: BoardSizeRecord,
    rotationRadians: Double?,
    cropCGRect: CGRect,
    geometry: CanvasMiniMapViewGeometry
) -> PosterBackedThumbnailLayout? {
    // ... 统一计算 mappedCenter / visibleRect / fullImageRect / rotationRadians
}

private func drawPosterBackedImage(
    _ image: CGImage,
    layout: PosterBackedThumbnailLayout,
    in context: CGContext,
    clipPath: CGPath?
) {
    context.saveGState()
    context.translateBy(x: layout.mappedCenter.x, y: layout.mappedCenter.y)
    context.rotate(by: layout.rotationRadians)
    if let clipPath {
        context.addPath(clipPath)
        context.clip()
    } else {
        context.clip(to: layout.visibleRect)
    }
    // ... 再统一处理 y 轴翻转后的 CGImage 绘制
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: logPosterBackedDraw(...) / logPosterBackedRenderedRegion(...) / logNodeRegionSamples(...)
// 功能说明: 修改后 trace 日志和 region sampling 会显式记录节点 kind，并覆盖 handDrawing。
private func logPosterBackedDraw(
    traceContext: BoardThumbnailTraceContext,
    kind: CanvasMiniMapNodeKind,
    itemID: UUID,
    documentOrder: Int?,
    renderOrder: Int,
    worldCenter: CGPoint,
    mappedCenter: CGPoint,
    visibleSize: CGSize,
    cropRect: CGRect,
    previewVisibleRect: CGRect,
    previewFullImageRect: CGRect,
    image: CGImage,
    rotationRadians: CGFloat,
    context: CGContext
) {
    print(
        "[BoardList][ThumbnailTrace][PosterDraw] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "kind=\(describeBoardThumbnailNodeKind(kind)) " +
            "itemID=\(itemID.uuidString) "
    )
}

private func logPosterBackedRenderedRegion(
    traceContext: BoardThumbnailTraceContext,
    kind: CanvasMiniMapNodeKind,
    itemID: UUID,
    documentOrder: Int?,
    renderOrder: Int,
    previewVisibleRect: CGRect,
    renderedImage: CGImage
) {
    print(
        "[BoardList][ThumbnailTrace][PosterDrawResult] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "kind=\(describeBoardThumbnailNodeKind(kind)) " +
            "itemID=\(itemID.uuidString) "
    )
}

private func logNodeRegionSamples(
    phase: String,
    traceContext: BoardThumbnailTraceContext,
    nodes: [CanvasMiniMapNode],
    geometry: CanvasMiniMapViewGeometry,
    image: CGImage
) {
    for node in nodes where node.kind == .image || node.kind == .handDrawing {
        // ... 对 image 和 handDrawing 都做采样签名记录
    }
}
```

## 修改四：抽共享纸面外观配置，收口 viewport 与 thumbnail 的 handDrawing 样式来源

### 修改前

- iOS / macOS viewport 各自维护一套相同的 handDrawing 白纸颜色、边框颜色、线宽和圆角常量。
- `applyHandDrawingAppearance(...)` 在两个平台里也是同一套赋值逻辑，只是各写一遍。
- thumbnail 侧没有共享外观来源，因此即使阶段 3 主画布已经有纸面样式，阶段 4 的 board list / persisted thumbnail 仍需要重新补同一套配置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: handDrawingPaperFillColor / handDrawingBorderColor / emptyHandDrawingBorderColor / applyHandDrawingAppearance(to:isEmpty:contentsScale:)
// 功能说明: 修改前 iOS viewport 直接在类内硬编码 handDrawing 样式常量，并在应用样式时直接读取 Self 上的静态值。
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
// 函数名: handDrawingPaperFillColor / handDrawingBorderColor / emptyHandDrawingBorderColor / applyHandDrawingAppearance(to:isEmpty:contentsScale:)
// 功能说明: 修改前 macOS viewport 也保留了一份相同的 handDrawing 样式常量，和 iOS 重复维护。
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

### 修改后

- 新增 `CanvasHandDrawingPreviewAppearance.swift`，把 `paperFillColor / borderColor / emptyBorderColor / borderLineWidth / cornerRadius` 收口到一个共享入口。
- iOS / macOS viewport 都改为读取这份共享常量。
- `BoardThumbnailRenderer` 的 `drawHandDrawingPaperFill(...)` / `drawHandDrawingPaperBorder(...)` 也直接读取同一份配置，根因上避免三套样式逐渐漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasHandDrawingPreviewAppearance.swift
// 函数名: CanvasHandDrawingPreviewAppearance / resolvedBorderColor(isEmpty:)
// 功能说明: 修改后新增共享纸面外观配置，主画布 viewport 和 thumbnail 都从同一个入口取样式。
enum CanvasHandDrawingPreviewAppearance {
    static let paperFillColor = CGColor(gray: 1, alpha: 1)
    static let borderColor = CGColor(
        red: 0.82,
        green: 0.84,
        blue: 0.88,
        alpha: 1
    )
    static let emptyBorderColor = CGColor(
        red: 0.68,
        green: 0.72,
        blue: 0.78,
        alpha: 1
    )
    static let borderLineWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 10

    static func resolvedBorderColor(isEmpty: Bool) -> CGColor {
        isEmpty ? emptyBorderColor : borderColor
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: applyHandDrawingAppearance(to:isEmpty:contentsScale:)
// 功能说明: 修改后 iOS viewport 直接复用共享 handDrawing 外观常量，不再在类内维护另一份配置。
private func applyHandDrawingAppearance(
    to handDrawingLayer: CanvasImageLayer,
    isEmpty: Bool,
    contentsScale: CGFloat
) {
    handDrawingLayer.backgroundColor =
        CanvasHandDrawingPreviewAppearance.paperFillColor
    handDrawingLayer.borderColor =
        CanvasHandDrawingPreviewAppearance.resolvedBorderColor(isEmpty: isEmpty)
    handDrawingLayer.borderWidth =
        CanvasHandDrawingPreviewAppearance.borderLineWidth / max(contentsScale, 1)
    handDrawingLayer.cornerRadius =
        CanvasHandDrawingPreviewAppearance.cornerRadius
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawHandDrawingPaperFill(layout:paperPath:in:) / drawHandDrawingPaperBorder(layout:paperPath:isEmpty:in:)
// 功能说明: 修改后 thumbnail 侧也复用同一份纸面配置，避免主画布和列表缩略图对空白手绘块画出不同样式。
private func drawHandDrawingPaperFill(
    layout: PosterBackedThumbnailLayout,
    paperPath: CGPath,
    in context: CGContext
) {
    context.saveGState()
    context.translateBy(x: layout.mappedCenter.x, y: layout.mappedCenter.y)
    context.rotate(by: layout.rotationRadians)
    context.setFillColor(CanvasHandDrawingPreviewAppearance.paperFillColor)
    context.addPath(paperPath)
    context.fillPath()
    context.restoreGState()
}

private func drawHandDrawingPaperBorder(
    layout: PosterBackedThumbnailLayout,
    paperPath: CGPath,
    isEmpty: Bool,
    in context: CGContext
) {
    context.saveGState()
    context.translateBy(x: layout.mappedCenter.x, y: layout.mappedCenter.y)
    context.rotate(by: layout.rotationRadians)
    context.setStrokeColor(
        CanvasHandDrawingPreviewAppearance.resolvedBorderColor(isEmpty: isEmpty)
    )
    context.setLineWidth(CanvasHandDrawingPreviewAppearance.borderLineWidth)
    context.addPath(paperPath)
    context.strokePath()
    context.restoreGState()
}
```

## 修改五：阶段 4 测试补齐为稳定链路验证，并新增空白缩略图可见性断言

### 修改前

- 仓库里没有 `MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests.swift`。
- `BoardHandDrawingStorageTests.swift` 只覆盖 save/load、overwrite、duplicate 等已有阶段，不验证：
  - `BoardGeometryPreviewBuilder` 是否保留 `handDrawing` 节点类型；
  - `makeSnapshot(from:)` 是否把 handDrawing 节点继续传给 minimap snapshot；
  - 空白 handDrawing 的 persisted thumbnail 是否仍然可见。

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() / BoardHandDrawingStorageTestError
// 功能说明: 修改前 storage 测试覆盖 duplicated handDrawing 存储后就结束，没有阶段 4 的 minimap/seed 类型断言，也没有空白缩略图可见性验证。
func testBoardStorePersistsDuplicatedHandDrawingWithIndependentAssetPaths() throws {
    try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
        // ... duplicated handDrawing 存储与重载验证
    }
}

private enum BoardHandDrawingStorageTestError: Error {
    case invalidImageEncoding
    case invalidImageDecoding
    case invalidBitmapContext
}
```

### 修改后

- 新增 `HandDrawingPreviewPipelineTests.swift`，稳定验证 `BoardGeometryPreviewBuilder` 产出的 seed / snapshot 都保留 `handDrawing` 节点语义。
- 在 `BoardHandDrawingStorageTests.swift` 中新增 `testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing()`。
- 新增 `sampleHandDrawingPixelColor(...)`，对持久化缩略图做 1x1 采样，直接断言空白手绘块缩略图不透明且接近白色纸面。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests.swift
// 函数名: testBoardGeometryPreviewBuilderMarksHandDrawingSeedNodeKind() / testBoardGeometryPreviewBuilderMakesMiniMapSnapshotWithHandDrawingNode()
// 功能说明: 修改后新增阶段 4 的 geometry preview 测试，确保 handDrawing 节点类型不会在 seed / snapshot 链路里退化为 image。
@MainActor
final class HandDrawingPreviewPipelineTests: XCTestCase {
    func testBoardGeometryPreviewBuilderMarksHandDrawingSeedNodeKind() {
        let handDrawingRecord = BoardHandDrawingItemRecord(
            id: itemID,
            center: BoardPointRecord(CGPoint(x: 60, y: 60)),
            size: BoardSizeRecord(CGSize(width: 80, height: 80)),
            zIndex: 2,
            paper: BoardHandDrawingPaperRecord(.square),
            isEmpty: true,
            contentRevision: UUID(),
            rotationRadians: Double.pi / 8
        )
        let document = makeHandDrawingPreviewTestDocument(
            boardID: UUID(),
            boardRect: boardRect,
            items: [.handDrawing(handDrawingRecord)]
        )

        let seed = BoardGeometryPreviewBuilder().makeSeed(from: document)
        XCTAssertEqual(seed.nodes.count, 1)
        XCTAssertEqual(node.id, handDrawingRecord.id)
        switch node.kind {
        case .handDrawing:
            break
        default:
            XCTFail("Expected handDrawing node kind, got \(node.kind).")
        }
    }

    func testBoardGeometryPreviewBuilderMakesMiniMapSnapshotWithHandDrawingNode() {
        let seed = builder.makeSeed(from: document)
        let snapshot = builder.makeSnapshot(from: seed)

        XCTAssertEqual(snapshot.boardWorldRect, boardRect)
        XCTAssertEqual(snapshot.displayWorldRect, boardRect)
        switch snapshot.nodes[0].kind {
        case .handDrawing:
            break
        default:
            XCTFail("Expected minimap snapshot to keep handDrawing node kind.")
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing()
// 功能说明: 修改后新增空白 handDrawing 缩略图验证，确保 persisted thumbnail 里仍能看到白纸而不是透明空洞。
func testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing() throws {
    try withTemporaryHandDrawingBoardWorkspace { _, userDefaults in
        let transparentPreviewImage = try makeHandDrawingTestImage(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        var item = makeHandDrawingItem(
            id: itemID,
            previewImage: transparentPreviewImage,
            contentRevision: UUID(),
            isEmpty: true
        )
        item.rotationRadians = 0

        try BoardStore.saveBoard(
            BoardSaveSnapshot(
                runtimeState: runtimeState,
                transientImageAssetPayloads: [:],
                transientHandDrawingAssetPayloads: [
                    itemID: BoardTransientHandDrawingAssetPayload(
                        itemID: itemID,
                        drawingData: drawingData,
                        previewImageData: try makeHandDrawingPNGData(
                            for: transparentPreviewImage
                        )
                    )
                ]
            ),
            userDefaults: userDefaults
        )

        let thumbnailImage = try decodeHandDrawingImage(
            at: BoardPersistedThumbnailStore.thumbnailURL(
                forBoardDirectoryURL: entry.boardDirectoryURL
            )
        )
        let averagePixel = try sampleHandDrawingPixelColor(in: thumbnailImage)

        XCTAssertGreaterThan(averagePixel.alpha, 200)
        XCTAssertGreaterThan(averagePixel.red, 200)
        XCTAssertGreaterThan(averagePixel.green, 200)
        XCTAssertGreaterThan(averagePixel.blue, 200)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests.swift
// 函数名: HandDrawingPixelColor / sampleHandDrawingPixelColor(in:)
// 功能说明: 修改后新增缩略图像素采样 helper，用于直接验证空白手绘块缩略图是否被画成可见纸面。
private struct HandDrawingPixelColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func sampleHandDrawingPixelColor(
    in image: CGImage
) throws -> HandDrawingPixelColor {
    var pixelBytes = [UInt8](repeating: 0, count: 4)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: &pixelBytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw BoardHandDrawingStorageTestError.invalidBitmapContext
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return HandDrawingPixelColor(
        red: pixelBytes[0],
        green: pixelBytes[1],
        blue: pixelBytes[2],
        alpha: pixelBytes[3]
    )
}
```

## 验证结果

- 定点测试：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests/testBoardStorePersistsVisibleThumbnailForEmptyHandDrawing"`  
    结果：通过。
- 构建验证：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS"`  
    结果：通过。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"`  
    结果：通过。
- Lint 验证：
  - 对本次涉及文件执行 `ReadLints`。  
    结果：没有新增 linter error。

## 阶段 4 完成标志对照

- minimap：已能为 handDrawing 生成独立节点，并复用旋转预览几何。
- `BoardPreviewSeed`：已保留 handDrawing 节点类型，不再写成 image。
- board list 缩略图 / persisted thumbnail：已通过 handDrawing 专用绘制路径渲染纸面与预览图。
- 空白 handDrawing：已通过存储测试验证其持久化缩略图仍然可见。
