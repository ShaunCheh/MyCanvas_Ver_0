# 20260323_153528_text_support_phase_t5_preview_regression_record

## 记录范围

- 记录内容：
  1. 将运行时 `minimap` 的 node provider 从 image-only 命名与组装方式，升级为真正的 mixed-item 感知，并让文本项能输出 `.text` 节点。
  2. 将 `BoardThumbnailRenderer` 从只绘制图片缩略图，升级为按 `BoardItemRecord` 顺序绘制 image/text mixed thumbnail。
  3. 在 `BoardPreviewProvider` 中为含文本的 board 增加保护，避免继续复用历史上不包含文本内容的 persisted thumbnail。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 相关但本次未改动：
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift` 其实已经可以把持久化的 `.text` record 转成 `CanvasMiniMapNode(kind: .text)`；`T-5` 实际补的是运行时 `minimap` provider 和真实 thumbnail 渲染缺口。
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - iOS / macOS 运行态手工全回归截图

## 修改一：运行时 `minimap` 从 image-only provider 升级为 mixed-item provider 组合

### 修改前

- `CanvasMiniMapNodeProviderContext` 与 `CanvasMiniMapRenderContext` 把 inline edit / rotation preview 明确命名为 image-only。
- 默认 `CanvasMiniMapRenderer` 只注册 `CanvasMiniMapImageNodeProvider`。
- `CanvasEditorSession.makeMiniMapSnapshot()` 也沿着 image-only 参数名把状态传入 minimap。
- 结果是：即便 `CanvasMiniMapNodeKind` 已经存在 `.text`，运行时 minimap snapshot 依然只会产出 image 节点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: N/A（CanvasMiniMapNodeProviderContext / CanvasMiniMapRenderContext / CanvasMiniMapImageNodeProvider）
// 功能说明: 修改前 minimap provider context 仍然把 inline edit / rotation preview 绑定到 image-only 语义；provider 也只会输出图片节点。
struct CanvasMiniMapNodeProviderContext {
    let scene: CanvasScene
    let imageInlineEditState: CanvasInlineEditState?
    let imageRotationPreviewState: CanvasRotationPreviewState?
}

struct CanvasMiniMapRenderContext {
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let nodeProviderContext: CanvasMiniMapNodeProviderContext

    init(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        imageInlineEditState: CanvasInlineEditState? = nil,
        imageRotationPreviewState: CanvasRotationPreviewState? = nil
    ) {
        self.init(
            boardState: boardState,
            camera: camera,
            nodeProviderContext: CanvasMiniMapNodeProviderContext(
                scene: scene,
                imageInlineEditState: imageInlineEditState,
                imageRotationPreviewState: imageRotationPreviewState
            )
        )
    }
}

struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.imageInlineEditState,
                rotationPreviewState: context.imageRotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: 修改前 minimap renderer 默认只注册图片 provider，因此 snapshot 不会包含 text node。
struct CanvasMiniMapRenderer {
    private let nodeProviders: [any CanvasMiniMapNodeProviding]

    init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
        self.nodeProviders = nodeProviders ?? [CanvasMiniMapImageNodeProvider()]
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: makeMiniMapSnapshot()
// 功能说明: 修改前 editor session 仍然沿用 image-only 参数名创建 minimap render context。
func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
    miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
}
```

### 修改后

- context 命名改为通用的 `inlineEditState` / `rotationPreviewState`，不再暗示 minimap 只能服务图片。
- 新增 `CanvasMiniMapTextNodeProvider`，从 `scene.orderedBoardItems()` 中提取 `textItem`，输出 `.text` 节点。
- `CanvasMiniMapRenderer` 默认组合 image/text 两个 provider，运行时 minimap snapshot 现在会自然覆盖 mixed board。
- 文本 inline edit 时，正在编辑的 text item 也会标记 `isPreviewActive`，保持与 minimap 现有 preview 扩展逻辑兼容。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: N/A（CanvasMiniMapNodeProviderContext / CanvasMiniMapRenderContext / CanvasMiniMapImageNodeProvider / CanvasMiniMapTextNodeProvider）
// 功能说明: 修改后 minimap provider context 不再写死 image-only 命名，并新增 text provider，将运行时文本项真正送入 minimap snapshot。
struct CanvasMiniMapNodeProviderContext {
    let scene: CanvasScene
    let inlineEditState: CanvasInlineEditState?
    let rotationPreviewState: CanvasRotationPreviewState?
}

struct CanvasMiniMapRenderContext {
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let nodeProviderContext: CanvasMiniMapNodeProviderContext

    init(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
    ) {
        self.init(
            boardState: boardState,
            camera: camera,
            nodeProviderContext: CanvasMiniMapNodeProviderContext(
                scene: scene,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        )
    }
}

struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.inlineEditState,
                rotationPreviewState: context.rotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}

struct CanvasMiniMapTextNodeProvider: CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedBoardItems().compactMap { boardItem in
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
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:)
// 功能说明: 修改后 minimap renderer 默认同时注册 image/text provider，snapshot 会按统一排序合并 mixed nodes。
struct CanvasMiniMapRenderer {
    private let nodeProviders: [any CanvasMiniMapNodeProviding]

    init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
        self.nodeProviders = nodeProviders ?? [
            CanvasMiniMapImageNodeProvider(),
            CanvasMiniMapTextNodeProvider()
        ]
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: makeMiniMapSnapshot()
// 功能说明: 修改后 editor session 用泛化后的 minimap render context 传递 inline edit / rotation preview 状态。
func makeMiniMapSnapshot() -> CanvasMiniMapSnapshot {
    miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
    )
}
```

## 修改二：`BoardThumbnailRenderer` 从 image-only 缩略图管线升级为 mixed board 绘制

### 修改前

- `renderThumbnail(for:)` 只把 `item.document.imageItemRecords` 送进渲染循环。
- `renderPersistedThumbnail(for:)` 依赖 `runtimeImageItems`，若 board 里没有图片就直接返回 `nil`。
- 私有 `renderThumbnail(...)` 只接受 `[BoardImageItemRecord]`，循环里永远只执行 `drawLoadedImage(...)`。
- 结果是 text-only board 无法生成 persisted thumbnail，mixed board 也只会渲染图片部分，文本内容不会进入列表缩略图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:) / renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:)
// 功能说明: 修改前 thumbnail renderer 的入口仍然是 image-only；text-only board 会直接拿不到真实 thumbnail。
final class BoardThumbnailRenderer {
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
            let decodeMaxPixelSize = self.decodeMaxPixelSize(
                for: itemRecord,
                geometry: geometry
            )
            return try self.loadAssetImage(
                for: itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                maxPixelSize: decodeMaxPixelSize
            )
        }
    }

    func renderPersistedThumbnail(
        for runtimeState: BoardRuntimeState,
        maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        let runtimeImageItems = runtimeState.imageItems
        guard runtimeImageItems.isEmpty == false else {
            return nil
        }

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
        // ... 省略 geometry / pixel size 计算 ...

        let runtimeItemsByID = Dictionary(
            uniqueKeysWithValues: runtimeImageItems.map { ($0.id, $0) }
        )
        return try renderThumbnail(
            itemRecords: document.imageItemRecords,
            previewSeed: previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: 0,
            cancellationCheck: cancellationCheck
        ) { itemRecord, _ in
            guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
                throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
                    itemID: itemRecord.id
                )
            }

            return runtimeItem.cgImage
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:imageProvider:)
// 功能说明: 修改前私有渲染循环只处理 BoardImageItemRecord，并且每一项都走图片 decode + drawLoadedImage 路径。
private func renderThumbnail(
    itemRecords: [BoardImageItemRecord],
    previewSeed: BoardPreviewSeed,
    targetPixelSize: CGSize,
    contentInset: CGFloat,
    cancellationCheck: () throws -> Void,
    imageProvider: (BoardImageItemRecord, CanvasMiniMapViewGeometry) throws -> CGImage
) throws -> CGImage? {
    guard itemRecords.isEmpty == false else {
        return nil
    }

    // ... 省略 bitmap context / geometry 初始化 ...

    for itemRecord in orderedItemRecords(from: itemRecords) {
        try cancellationCheck()
        let image = try imageProvider(itemRecord, geometry)
        try cancellationCheck()
        drawLoadedImage(
            image,
            for: itemRecord,
            geometry: geometry,
            in: context
        )
    }

    try cancellationCheck()
    return context.makeImage()
}
```

### 修改后

- 顶层入口改为直接接受 `item.document.items` / `document.items`，缩略图绘制顺序与 mixed board 文档顺序保持一致。
- `renderPersistedThumbnail(for:)` 改为只要 `runtimeState.items` 非空就允许生成 persisted thumbnail，因此 text-only board 也能产出缩略图。
- 私有渲染循环改为处理 `[BoardItemRecord]`，在循环里按 `.image` / `.text` 分支渲染。
- 对文本项新增 `drawTextItem(...)`、`drawText(...)`、`fittedTextFont(...)`、`measureText(...)`、`textParagraphStyle()`、`textAttributes(...)`、`textFont(...)`、`textColor(...)`，用 `CoreText` 在 thumbnail `CGContext` 中完成轻量文本排版。
- 图片渲染逻辑保留原有 `drawLoadedImage(...)`、crop 映射和 rotation 语义，因此 image board 行为不需要绕开原实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:) / renderPersistedThumbnail(for:maximumLongestSide:cancellationCheck:) / renderThumbnail(itemRecords:previewSeed:targetPixelSize:contentInset:cancellationCheck:imageProvider:)
// 功能说明: 修改后 thumbnail renderer 直接按 mixed BoardItemRecord 渲染；图片继续走原有 decode/draw 路径，文本则在同一上下文里单独排版绘制。
import CoreGraphics
import CoreText
import Foundation
import ImageIO

final class BoardThumbnailRenderer {
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
            let decodeMaxPixelSize = self.decodeMaxPixelSize(
                for: itemRecord,
                geometry: geometry
            )
            return try self.loadAssetImage(
                for: itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                maxPixelSize: decodeMaxPixelSize
            )
        }
    }

    func renderPersistedThumbnail(
        for runtimeState: BoardRuntimeState,
        maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        guard runtimeState.items.isEmpty == false else {
            return nil
        }

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
        // ... 省略 geometry / pixel size 计算 ...

        let runtimeItemsByID = Dictionary(
            uniqueKeysWithValues: runtimeState.imageItems.map { ($0.id, $0) }
        )
        return try renderThumbnail(
            itemRecords: document.items,
            previewSeed: previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: 0,
            cancellationCheck: cancellationCheck
        ) { itemRecord, _ in
            guard let runtimeItem = runtimeItemsByID[itemRecord.id] else {
                throw BoardThumbnailRendererError.invalidRuntimeImageAsset(
                    itemID: itemRecord.id
                )
            }

            return runtimeItem.cgImage
        }
    }

    private func renderThumbnail(
        itemRecords: [BoardItemRecord],
        previewSeed: BoardPreviewSeed,
        targetPixelSize: CGSize,
        contentInset: CGFloat,
        cancellationCheck: () throws -> Void,
        imageProvider: (BoardImageItemRecord, CanvasMiniMapViewGeometry) throws -> CGImage
    ) throws -> CGImage? {
        guard itemRecords.isEmpty == false else {
            return nil
        }

        // ... 省略 bitmap context / geometry 初始化 ...

        for itemRecord in orderedItemRecords(from: itemRecords) {
            try cancellationCheck()
            switch itemRecord {
            case let .image(imageItemRecord):
                let image = try imageProvider(imageItemRecord, geometry)
                try cancellationCheck()
                drawLoadedImage(
                    image,
                    for: imageItemRecord,
                    geometry: geometry,
                    in: context
                )
            case let .text(textItemRecord):
                drawTextItem(
                    textItemRecord,
                    geometry: geometry,
                    in: context
                )
            }
        }

        try cancellationCheck()
        return context.makeImage()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawTextItem(_:) / drawText(_:style:in:worldToPixelScale:context:) / fittedTextFont(...) / measureText(...) / textParagraphStyle() / textAttributes(...) / textFont(named:size:) / textColor(for:)
// 功能说明: 修改后 thumbnail renderer 新增一组 CoreText helper，在缩略图上下文中完成文本项的旋转、裁切框映射、字体拟合与颜色绘制。
private func drawTextItem(
    _ itemRecord: BoardTextItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext
) {
    guard itemRecord.text.isEmpty == false else {
        return
    }

    let visibleSize = itemRecord.size.cgSize
    guard visibleSize.width > 0, visibleSize.height > 0 else {
        return
    }

    let mappedVisibleSize = CGSize(
        width: visibleSize.width * geometry.scale,
        height: visibleSize.height * geometry.scale
    )
    guard mappedVisibleSize.width > 0, mappedVisibleSize.height > 0 else {
        return
    }

    let mappedCenter = geometry.worldToMiniMap(itemRecord.center.cgPoint)
    let textRect = CGRect(
        x: -mappedVisibleSize.width / 2,
        y: -mappedVisibleSize.height / 2,
        width: mappedVisibleSize.width,
        height: mappedVisibleSize.height
    ).standardized
    let rotationRadians = normalizedCanvasAngle(
        CGFloat(itemRecord.rotationRadians ?? 0)
    )

    context.saveGState()
    context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
    context.rotate(by: rotationRadians)
    context.clip(to: textRect)
    drawText(
        itemRecord.text,
        style: itemRecord.style,
        in: textRect,
        worldToPixelScale: geometry.scale,
        context: context
    )
    context.restoreGState()
}

private func drawText(
    _ text: String,
    style: BoardTextStyleRecord,
    in rect: CGRect,
    worldToPixelScale: CGFloat,
    context: CGContext
) {
    let availableSize = rect.size
    guard availableSize.width > 0, availableSize.height > 0 else {
        return
    }

    let paragraphStyle = textParagraphStyle()
    let font = fittedTextFont(
        for: text,
        style: style,
        availableSize: availableSize,
        worldToPixelScale: worldToPixelScale,
        paragraphStyle: paragraphStyle
    )
    let attributedText = NSAttributedString(
        string: text,
        attributes: textAttributes(
            font: font,
            paragraphStyle: paragraphStyle,
            color: textColor(for: style.color)
        )
    )
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let textBounds = CGRect(origin: .zero, size: availableSize)

    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.textMatrix = .identity
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        CGPath(rect: textBounds, transform: nil),
        nil
    )
    CTFrameDraw(frame, context)
    context.restoreGState()
}

private func fittedTextFont(
    for text: String,
    style: BoardTextStyleRecord,
    availableSize: CGSize,
    worldToPixelScale: CGFloat,
    paragraphStyle: CTParagraphStyle
) -> CTFont {
    let baseFontSize = max(CGFloat(style.fontSize) * worldToPixelScale, 1)
    let baseFont = textFont(named: style.fontName, size: baseFontSize)
    let intrinsicSize = measureText(
        text,
        font: baseFont,
        paragraphStyle: paragraphStyle
    )
    guard
        availableSize.width > 0,
        availableSize.height > 0,
        intrinsicSize.width > 0,
        intrinsicSize.height > 0
    else {
        return baseFont
    }

    let scale = min(
        availableSize.width / intrinsicSize.width,
        availableSize.height / intrinsicSize.height
    )
    guard scale.isFinite, scale > 0 else {
        return baseFont
    }

    return textFont(
        named: style.fontName,
        size: max(baseFontSize * scale, 1)
    )
}

private func measureText(
    _ text: String,
    font: CTFont,
    paragraphStyle: CTParagraphStyle
) -> CGSize {
    let attributedText = NSAttributedString(
        string: text,
        attributes: textAttributes(
            font: font,
            paragraphStyle: paragraphStyle
        )
    )
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributedText as CFAttributedString
    )
    let measuredSize = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributedText.length),
        nil,
        CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ),
        nil
    )
    return CGSize(
        width: ceil(max(measuredSize.width, 0)),
        height: ceil(max(measuredSize.height, 0))
    )
}

private func textParagraphStyle() -> CTParagraphStyle {
    var alignment = CTTextAlignment.center
    var lineBreakMode = CTLineBreakMode.byClipping
    return withUnsafePointer(to: &alignment) { alignmentPointer in
        withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
            let settings = [
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: alignmentPointer
                ),
                CTParagraphStyleSetting(
                    spec: .lineBreakMode,
                    valueSize: MemoryLayout<CTLineBreakMode>.size,
                    value: lineBreakModePointer
                )
            ]
            return settings.withUnsafeBufferPointer { buffer in
                CTParagraphStyleCreate(buffer.baseAddress!, buffer.count)
            }
        }
    }
}

private func textAttributes(
    font: CTFont,
    paragraphStyle: CTParagraphStyle,
    color: CGColor? = nil
) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
        NSAttributedString.Key(
            rawValue: kCTParagraphStyleAttributeName as String
        ): paragraphStyle
    ]
    if let color {
        attributes[
            NSAttributedString.Key(
                rawValue: kCTForegroundColorAttributeName as String
            )
        ] = color
    }
    return attributes
}

private func textFont(
    named fontName: String,
    size: CGFloat
) -> CTFont {
    let resolvedSize = max(size, 1)
    guard fontName.isEmpty == false, fontName != "System" else {
        return CTFontCreateUIFontForLanguage(
            .system,
            resolvedSize,
            nil
        ) ?? CTFontCreateWithName(
            "Helvetica" as CFString,
            resolvedSize,
            nil
        )
    }

    return CTFontCreateWithName(
        fontName as CFString,
        resolvedSize,
        nil
    )
}

private func textColor(for colorRecord: BoardTextColorRecord) -> CGColor {
    let color = colorRecord.canvasTextColor
    return CGColor(
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: color.alpha
    )
}
```

## 修改三：`BoardPreviewProvider` 为含文本 board 禁用旧 persisted thumbnail 直出

### 修改前

- `loadPersistedThumbnailPreview(...)` 只要本地 `thumbnail.png` 足够新，就直接读取并返回。
- 这对 image-only board 没问题，但对于已经升级到 mixed/text board 的数据，如果磁盘上保留的是“文本支持落地前”的旧 PNG，就会造成 catalog 继续显示缺失文本的历史缩略图。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 功能说明: 修改前 provider 不区分 image-only 与 mixed/text board；只要 persisted thumbnail 足够新就会直接复用。
private func loadPersistedThumbnailPreview(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    let decodeMaxPixelSize = max(
        cacheKey.pixelWidth,
        cacheKey.pixelHeight
    )
    guard
        let persistedThumbnail = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
            at: item.persistedThumbnailURL,
            updatedAt: item.updatedAt,
            maxPixelSize: decodeMaxPixelSize
        )
    else {
        return nil
    }

    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        fromPersistedThumbnail: persistedThumbnail,
        previewSeed: item.previewSeed,
        targetPixelSize: cacheKey.pixelSize,
        cancellationCheck: cancellationCheck
    )
}
```

### 修改后

- 增加 `guard item.document.textItemRecords.isEmpty else { return nil }`。
- 只要 board 含有文本项，就强制走当前版本的 `BoardThumbnailRenderer.renderThumbnail(for:)` 动态重绘路径，而不是继续沿用可能缺失文本内容的旧 persisted thumbnail。
- 这样 mixed board / text-only board 在 catalog preview 中会优先展示当前文档真实内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名: loadPersistedThumbnailPreview(for:cacheKey:cancellationCheck:)
// 功能说明: 修改后 provider 会主动跳过含文本 board 的旧 persisted thumbnail，避免历史 PNG 继续漏掉文本内容。
private func loadPersistedThumbnailPreview(
    for item: BoardCatalogItem,
    cacheKey: BoardThumbnailCacheKey,
    cancellationCheck: () throws -> Void = {}
) throws -> CGImage? {
    // Older persisted thumbnails may predate text rendering support, so mixed
    // and text-only boards should be regenerated from the current document.
    guard item.document.textItemRecords.isEmpty else {
        return nil
    }

    let decodeMaxPixelSize = max(
        cacheKey.pixelWidth,
        cacheKey.pixelHeight
    )
    guard
        let persistedThumbnail = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
            at: item.persistedThumbnailURL,
            updatedAt: item.updatedAt,
            maxPixelSize: decodeMaxPixelSize
        )
    else {
        return nil
    }

    try cancellationCheck()
    return try thumbnailRenderer.renderThumbnail(
        fromPersistedThumbnail: persistedThumbnail,
        previewSeed: item.previewSeed,
        targetPixelSize: cacheKey.pixelSize,
        cancellationCheck: cancellationCheck
    )
}
```

## 验证与限制

### 已执行验证

- `ReadLints` 检查本次修改文件：无 IDE 诊断错误。
- 使用 `xcrun --sdk macosx swiftc -typecheck -parse-as-library` 对整个 `MyCanvas_Ver_0` 源码树做静态检查：通过。

```sh
# 命令说明: 对整个源码树做 macOS 静态 typecheck，确认 shared + macOS 编译面没有语法或类型错误。
python3 - <<'PY'
import pathlib
import subprocess
import sys
root = pathlib.Path('MyCanvas_Ver_0')
files = sorted(str(path) for path in root.rglob('*.swift'))
cmd = ['xcrun', '--sdk', 'macosx', 'swiftc', '-typecheck', '-parse-as-library', *files]
result = subprocess.run(cmd)
sys.exit(result.returncode)
PY
```

```text
# 结果摘要: 退出码 0，无输出。
```

### 当前限制

- 当前机器的 active developer directory 仍指向 Command Line Tools，`xcodebuild` 不可用，因此这次记录无法附带完整的 simulator / app runtime 回归。
- iOS / macOS 运行态的 `image import`、`crop`、`undo/redo`、`mixed save/load`、`text-only save/load`、`catalog preview` 手工点击路径，需要后续在完整 Xcode 环境中继续补验。

```sh
# 命令说明: 尝试列出 Xcode project schemes，用于后续完整构建/运行验证。
xcodebuild -list -project "MyCanvas_Ver_0.xcodeproj"
```

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

## 结果小结

- 运行时 `minimap` 现在会输出 `.text` 节点，文本项不再只存在于主画布。
- `board list` 的真实 thumbnail 现在可以覆盖 image-only、text-only、mixed 三种 board 形态。
- 含文本 board 会绕开旧 persisted thumbnail，减少 catalog 继续显示“少文本内容的历史 PNG”这一类回归。
