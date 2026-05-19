import CoreGraphics
import CoreText
import Foundation

private struct BoardThumbnailTraceContext {
    let mode: String
    let boardID: UUID?
    let documentOrderByID: [UUID: Int]
}

private struct PosterBackedThumbnailLayout {
    let mappedCenter: CGPoint
    let visibleRect: CGRect
    let fullImageRect: CGRect
    let rotationRadians: CGFloat
    let previewVisibleRect: CGRect
    let previewFullImageRect: CGRect
}

enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidRuntimePreviewAsset(itemID: UUID)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidBitmapContext:
            return "The thumbnail bitmap context could not be created."
        case let .invalidRuntimePreviewAsset(itemID):
            return "The runtime preview asset for board item \(itemID.uuidString) is missing."
        case .cancelled:
            return "The thumbnail request was cancelled."
        }
    }
}

final class BoardThumbnailRenderer {
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver

    init(
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver()
    ) {
        self.geometryPreviewBuilder = geometryPreviewBuilder
        self.mediaPosterImageResolver = mediaPosterImageResolver
    }

    func renderThumbnail(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
            BoardPreviewContent.animatedImagePreviewMode,
        contentInset: CGFloat = 10,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        try renderCatalogItemThumbnail(
            item,
            targetPixelSize: targetPixelSize,
            animatedImagePreviewMode: animatedImagePreviewMode,
            contentInset: contentInset,
            traceMode: "catalog-fresh",
            cancellationCheck: cancellationCheck
        )
    }

    func renderPersistedThumbnail(
        for item: BoardCatalogItem,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
            BoardPersistedThumbnailStore.animatedImagePreviewMode,
        maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        let targetPixelSize = persistedTargetPixelSize(
            for: item.previewSeed,
            maximumLongestSide: maximumLongestSide
        )
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            return nil
        }

        return try renderCatalogItemThumbnail(
            item,
            targetPixelSize: targetPixelSize,
            animatedImagePreviewMode: animatedImagePreviewMode,
            contentInset: 0,
            traceMode: "persist-rebuild",
            cancellationCheck: cancellationCheck
        )
    }

    private func renderCatalogItemThumbnail(
        _ item: BoardCatalogItem,
        targetPixelSize: CGSize,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        contentInset: CGFloat,
        traceMode: String,
        cancellationCheck: () throws -> Void
    ) throws -> CGImage? {
        var cachedImagesByFilename: [String: CGImage] = [:]
        var decodeMaxPixelSizesByFilename: [String: Int] = [:]
        let traceContext = makeTraceContext(
            mode: traceMode,
            boardID: item.boardID,
            itemRecords: item.document.items
        )
        return try renderThumbnail(
            itemRecords: item.document.items,
            previewSeed: item.previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: contentInset,
            cancellationCheck: cancellationCheck,
            traceContext: traceContext
        ) { itemRecord, geometry, itemRecords in
            if decodeMaxPixelSizesByFilename.isEmpty {
                decodeMaxPixelSizesByFilename = self.decodeMaxPixelSizesByFilename(
                    from: itemRecords,
                    geometry: geometry
                )
            }
            let previewAssetFilename = self.mediaPosterImageResolver
                .previewAssetFilename(for: itemRecord)
            let decodeMaxPixelSize = decodeMaxPixelSizesByFilename[
                previewAssetFilename
            ] ?? self.decodeMaxPixelSize(
                for: itemRecord,
                geometry: geometry
            )
            if let cachedImage = cachedImagesByFilename[previewAssetFilename] {
                return cachedImage
            }

            let image = try self.loadAssetPreviewImage(
                for: itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                animatedImagePreviewMode: animatedImagePreviewMode,
                maxPixelSize: decodeMaxPixelSize
            )
            cachedImagesByFilename[previewAssetFilename] = image
            return image
        }
    }

    func renderPersistedThumbnail(
        for runtimeState: BoardRuntimeState,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode =
            BoardPersistedThumbnailStore.animatedImagePreviewMode,
        maximumLongestSide: CGFloat = BoardPersistedThumbnailStore.maximumLongestSide,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        guard runtimeState.items.isEmpty == false else {
            return nil
        }

        let document = BoardDocumentMapper.makeDocument(from: runtimeState)
        let previewSeed = geometryPreviewBuilder.makeSeed(from: document)
        let targetPixelSize = persistedTargetPixelSize(
            for: previewSeed,
            maximumLongestSide: maximumLongestSide
        )
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            return nil
        }

        let runtimePreviewImagesByID = runtimeState.items.reduce(
            into: [UUID: CGImage]()
        ) { partialResult, item in
            switch item {
            case let .image(runtimeImageItem):
                partialResult[runtimeImageItem.id] = runtimeImageItem.posterCGImage
            case let .handDrawing(runtimeHandDrawingItem):
                partialResult[runtimeHandDrawingItem.id] = runtimeHandDrawingItem
                    .previewAsset
                    .posterCGImage
            case .text, .markdown:
                break
            }
        }
        let traceContext = makeTraceContext(
            mode: "persist-write",
            boardID: runtimeState.boardID,
            itemRecords: document.items
        )
        return try renderThumbnail(
            itemRecords: document.items,
            previewSeed: previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: 0,
            cancellationCheck: cancellationCheck,
            traceContext: traceContext
        ) { itemRecord, _, _ in
            guard let previewImage = runtimePreviewImagesByID[itemRecord.id] else {
                throw BoardThumbnailRendererError.invalidRuntimePreviewAsset(
                    itemID: itemRecord.id
                )
            }

            // Persisted board thumbnails stay static even for GIF boards; the
            // runtime preview image is the single frame we rasterize into thumbnail.png.
            guard animatedImagePreviewMode == .posterFrameOnly else {
                return previewImage
            }
            return previewImage
        }
    }

    func renderThumbnail(
        fromPersistedThumbnail persistedThumbnail: CGImage,
        previewSeed: BoardPreviewSeed,
        boardID: UUID? = nil,
        targetPixelSize: CGSize,
        contentInset: CGFloat = 10,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
        guard
            normalizedTargetPixelSize.width > 0,
            normalizedTargetPixelSize.height > 0
        else {
            return nil
        }
        let traceContext = BoardThumbnailTraceContext(
            mode: "persisted-replay",
            boardID: boardID,
            documentOrderByID: [:]
        )

        let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: CGRect(origin: .zero, size: normalizedTargetPixelSize),
                contentInset: contentInset
            ),
            let context = try makeBitmapContext(pixelSize: normalizedTargetPixelSize)
        else {
            return nil
        }

        // Persisted thumbnails are already rasterized in the preview's final
        // orientation, so replay them in bitmap-space instead of flipping again.
        prepareBitmapReplayContext(
            context,
            pixelSize: normalizedTargetPixelSize
        )
        let bitmapReplayRect = bitmapReplayRect(
            fromPreviewRect: geometry.contentRect,
            pixelSize: normalizedTargetPixelSize
        )
        if let persistedThumbnailGeometry = imageGeometry(
            for: persistedThumbnail,
            displayWorldRect: snapshot.displayWorldRect,
            contentInset: 0
        ) {
            logNodeRegionSamples(
                phase: "persisted-replay-input",
                traceContext: traceContext,
                nodes: previewSeed.nodes,
                geometry: persistedThumbnailGeometry,
                image: persistedThumbnail
            )
        }
        logRenderSurface(
            traceContext: traceContext,
            previewSeed: previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: contentInset,
            geometry: geometry,
            context: context
        )
        try cancellationCheck()
        logPersistedReplayDraw(
            traceContext: traceContext,
            previewRect: geometry.contentRect,
            bitmapReplayRect: bitmapReplayRect,
            persistedThumbnail: persistedThumbnail,
            context: context
        )
        context.draw(persistedThumbnail, in: bitmapReplayRect)
        try cancellationCheck()
        let renderedImage = context.makeImage()
        if let renderedImage {
            logNodeRegionSamples(
                phase: "persisted-replay-output",
                traceContext: traceContext,
                nodes: previewSeed.nodes,
                geometry: geometry,
                image: renderedImage
            )
            logRenderedImage(
                traceContext: traceContext,
                image: renderedImage
            )
        }
        return renderedImage
    }

    private func renderThumbnail(
        itemRecords: [BoardItemRecord],
        previewSeed: BoardPreviewSeed,
        targetPixelSize: CGSize,
        contentInset: CGFloat,
        cancellationCheck: () throws -> Void,
        traceContext: BoardThumbnailTraceContext,
        imageProvider: (
            BoardImageItemRecord,
            CanvasMiniMapViewGeometry,
            [BoardItemRecord]
        ) throws -> CGImage
    ) throws -> CGImage? {
        guard itemRecords.isEmpty == false else {
            return nil
        }

        let normalizedTargetPixelSize = normalizedPixelSize(targetPixelSize)
        guard
            normalizedTargetPixelSize.width > 0,
            normalizedTargetPixelSize.height > 0
        else {
            return nil
        }

        let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: CGRect(origin: .zero, size: normalizedTargetPixelSize),
                contentInset: contentInset
            ),
            let context = try makeBitmapContext(pixelSize: normalizedTargetPixelSize)
        else {
            return nil
        }

        prepareVectorRenderContext(
            context,
            pixelSize: normalizedTargetPixelSize
        )
        logRenderSurface(
            traceContext: traceContext,
            previewSeed: previewSeed,
            targetPixelSize: targetPixelSize,
            contentInset: contentInset,
            geometry: geometry,
            context: context
        )

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
                    documentOrder: traceContext.documentOrderByID[
                        imageItemRecord.id
                    ],
                    renderOrder: renderOrder
                )
            case let .text(textItemRecord):
                drawTextItem(
                    textItemRecord,
                    geometry: geometry,
                    in: context,
                    traceContext: traceContext,
                    documentOrder: traceContext.documentOrderByID[
                        textItemRecord.id
                    ],
                    renderOrder: renderOrder
                )
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
                    documentOrder: traceContext.documentOrderByID[
                        markdownItemRecord.id
                    ],
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
                    documentOrder: traceContext.documentOrderByID[
                        handDrawingItemRecord.id
                    ],
                    renderOrder: renderOrder
                )
            }
        }

        try cancellationCheck()
        let renderedImage = context.makeImage()
        if let renderedImage {
            logRenderedImage(
                traceContext: traceContext,
                image: renderedImage
            )
        }
        return renderedImage
    }

    private func makeBitmapContext(
        pixelSize: CGSize
    ) throws -> CGContext? {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return nil
        }

        guard
            let context = CGContext(
                data: nil,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw BoardThumbnailRendererError.invalidBitmapContext
        }

        return context
    }

    private func prepareVectorRenderContext(
        _ context: CGContext,
        pixelSize: CGSize
    ) {
        prepareBaseContext(
            context,
            pixelSize: pixelSize
        )

        // Flip into a top-left coordinate space so thumbnail drawing matches the
        // preview view and the canvas layer pipeline.
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: 1, y: -1)
    }

    private func prepareBitmapReplayContext(
        _ context: CGContext,
        pixelSize: CGSize
    ) {
        prepareBaseContext(
            context,
            pixelSize: pixelSize
        )
    }

    private func prepareBaseContext(
        _ context: CGContext,
        pixelSize: CGSize
    ) {
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: pixelSize.width,
                height: pixelSize.height
            )
        )
    }

    private func normalizedPixelSize(
        _ targetPixelSize: CGSize
    ) -> CGSize {
        guard
            targetPixelSize.width.isFinite,
            targetPixelSize.height.isFinite,
            targetPixelSize.width > 0,
            targetPixelSize.height > 0
        else {
            return .zero
        }

        return CGSize(
            width: max(targetPixelSize.width.rounded(.up), 1),
            height: max(targetPixelSize.height.rounded(.up), 1)
        )
    }

    private func persistedTargetPixelSize(
        for previewSeed: BoardPreviewSeed,
        maximumLongestSide: CGFloat
    ) -> CGSize {
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
        return BoardPersistedThumbnailStore.pixelSize(
            forDisplayWorldRect: snapshot.displayWorldRect,
            maximumLongestSide: maximumLongestSide
        )
    }

    private func decodeMaxPixelSizesByFilename(
        from itemRecords: [BoardItemRecord],
        geometry: CanvasMiniMapViewGeometry
    ) -> [String: Int] {
        var resolvedMaxPixelSizesByFilename: [String: Int] = [:]

        for itemRecord in itemRecords {
            let imageItemRecord: BoardImageItemRecord
            switch itemRecord {
            case let .image(record):
                imageItemRecord = record
            case let .handDrawing(record):
                imageItemRecord = record.previewImageRecord
            case .text, .markdown:
                continue
            }

            let decodeMaxPixelSize = decodeMaxPixelSize(
                for: imageItemRecord,
                geometry: geometry
            )
            let previewAssetFilename = mediaPosterImageResolver
                .previewAssetFilename(for: imageItemRecord)
            let existingPixelSize = resolvedMaxPixelSizesByFilename[
                previewAssetFilename
            ] ?? 0
            resolvedMaxPixelSizesByFilename[previewAssetFilename] = max(
                existingPixelSize,
                decodeMaxPixelSize
            )
        }

        return resolvedMaxPixelSizesByFilename
    }

    private func drawImageItem(
        _ image: CGImage,
        for itemRecord: BoardImageItemRecord,
        geometry: CanvasMiniMapViewGeometry,
        in context: CGContext,
        traceContext: BoardThumbnailTraceContext,
        documentOrder: Int?,
        renderOrder: Int
    ) {
        let cropRect = itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage
        let cropCGRect = cropRect.cgRect
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

        logPosterBackedDraw(
            traceContext: traceContext,
            kind: .image,
            itemID: itemRecord.id,
            documentOrder: documentOrder,
            renderOrder: renderOrder,
            worldCenter: itemRecord.center.cgPoint,
            mappedCenter: layout.mappedCenter,
            visibleSize: itemRecord.size.cgSize,
            cropRect: cropCGRect,
            previewVisibleRect: layout.previewVisibleRect,
            previewFullImageRect: layout.previewFullImageRect,
            image: image,
            rotationRadians: layout.rotationRadians,
            context: context
        )

        drawPosterBackedImage(
            image,
            layout: layout,
            in: context,
            clipPath: nil
        )
        if let renderedImage = context.makeImage() {
            logPosterBackedRenderedRegion(
                traceContext: traceContext,
                kind: .image,
                itemID: itemRecord.id,
                documentOrder: documentOrder,
                renderOrder: renderOrder,
                previewVisibleRect: layout.previewVisibleRect,
                renderedImage: renderedImage
            )
        }
    }

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

        logPosterBackedDraw(
            traceContext: traceContext,
            kind: .handDrawing,
            itemID: itemRecord.id,
            documentOrder: documentOrder,
            renderOrder: renderOrder,
            worldCenter: itemRecord.center.cgPoint,
            mappedCenter: layout.mappedCenter,
            visibleSize: itemRecord.size.cgSize,
            cropRect: cropCGRect,
            previewVisibleRect: layout.previewVisibleRect,
            previewFullImageRect: layout.previewFullImageRect,
            image: image,
            rotationRadians: layout.rotationRadians,
            context: context
        )

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
        if let renderedImage = context.makeImage() {
            logPosterBackedRenderedRegion(
                traceContext: traceContext,
                kind: .handDrawing,
                itemID: itemRecord.id,
                documentOrder: documentOrder,
                renderOrder: renderOrder,
                previewVisibleRect: layout.previewVisibleRect,
                renderedImage: renderedImage
            )
        }
    }

    private func makePosterBackedLayout(
        center: BoardPointRecord,
        size: BoardSizeRecord,
        rotationRadians: Double?,
        cropCGRect: CGRect,
        geometry: CanvasMiniMapViewGeometry
    ) -> PosterBackedThumbnailLayout? {
        let visibleSize = size.cgSize
        guard
            visibleSize.width > 0,
            visibleSize.height > 0,
            cropCGRect.width > 0,
            cropCGRect.height > 0
        else {
            return nil
        }

        let mappedVisibleSize = CGSize(
            width: visibleSize.width * geometry.scale,
            height: visibleSize.height * geometry.scale
        )
        guard mappedVisibleSize.width > 0, mappedVisibleSize.height > 0 else {
            return nil
        }

        let fullImagePreviewSize = CGSize(
            width: mappedVisibleSize.width / cropCGRect.width,
            height: mappedVisibleSize.height / cropCGRect.height
        )
        let mappedCenter = geometry.worldToMiniMap(center.cgPoint)
        let visibleRect = CGRect(
            x: -mappedVisibleSize.width / 2,
            y: -mappedVisibleSize.height / 2,
            width: mappedVisibleSize.width,
            height: mappedVisibleSize.height
        ).standardized
        let fullImageRect = CGRect(
            x: visibleRect.minX - (cropCGRect.minX * fullImagePreviewSize.width),
            y: visibleRect.minY - (cropCGRect.minY * fullImagePreviewSize.height),
            width: fullImagePreviewSize.width,
            height: fullImagePreviewSize.height
        ).standardized
        let resolvedRotationRadians = normalizedCanvasAngle(
            CGFloat(rotationRadians ?? 0)
        )

        return PosterBackedThumbnailLayout(
            mappedCenter: mappedCenter,
            visibleRect: visibleRect,
            fullImageRect: fullImageRect,
            rotationRadians: resolvedRotationRadians,
            previewVisibleRect: visibleRect.offsetBy(
                dx: mappedCenter.x,
                dy: mappedCenter.y
            ),
            previewFullImageRect: fullImageRect.offsetBy(
                dx: mappedCenter.x,
                dy: mappedCenter.y
            )
        )
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
        context.saveGState()
        // `CGImage` drawing still uses Quartz's native y-up sampling, so compensate
        // locally after the thumbnail surface has already been flipped into y-down.
        context.translateBy(x: layout.fullImageRect.minX, y: layout.fullImageRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(origin: .zero, size: layout.fullImageRect.size)
        )
        context.restoreGState()
        context.restoreGState()
    }

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

    private func handDrawingPaperPath(for visibleRect: CGRect) -> CGPath {
        let resolvedCornerRadius = min(
            CanvasHandDrawingPreviewAppearance.cornerRadius,
            min(visibleRect.width, visibleRect.height) / 2
        )
        return CGPath(
            roundedRect: visibleRect,
            cornerWidth: resolvedCornerRadius,
            cornerHeight: resolvedCornerRadius,
            transform: nil
        )
    }

    private func drawTextItem(
        _ itemRecord: BoardTextItemRecord,
        geometry: CanvasMiniMapViewGeometry,
        in context: CGContext,
        traceContext: BoardThumbnailTraceContext,
        documentOrder: Int?,
        renderOrder: Int
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
        let previewTextRect = textRect.offsetBy(
            dx: mappedCenter.x,
            dy: mappedCenter.y
        )

        logTextDraw(
            traceContext: traceContext,
            itemID: itemRecord.id,
            documentOrder: documentOrder,
            renderOrder: renderOrder,
            worldCenter: itemRecord.center.cgPoint,
            mappedCenter: mappedCenter,
            visibleSize: visibleSize,
            previewTextRect: previewTextRect,
            rotationRadians: rotationRadians,
            context: context
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
        let font = renderTextFont(
            style: style,
            worldToPixelScale: worldToPixelScale
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

    private func renderTextFont(
        style: BoardTextStyleRecord,
        worldToPixelScale: CGFloat
    ) -> CTFont {
        return textFont(
            named: style.fontName,
            size: CanvasTextLayoutMeasurer.renderFontSize(
                for: style.canvasTextStyle,
                scale: worldToPixelScale
            )
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

    private func decodeMaxPixelSize(
        for itemRecord: BoardImageItemRecord,
        geometry: CanvasMiniMapViewGeometry
    ) -> Int {
        let visibleSize = itemRecord.size.cgSize
        let cropRect = itemRecord.cropRectNormalized?.canvasImageCropRect ?? .fullImage
        let cropCGRect = cropRect.cgRect
        guard
            visibleSize.width > 0,
            visibleSize.height > 0,
            cropCGRect.width > 0,
            cropCGRect.height > 0
        else {
            return 64
        }

        let mappedVisibleSize = CGSize(
            width: visibleSize.width * geometry.scale,
            height: visibleSize.height * geometry.scale
        )
        let fullImagePreviewSize = CGSize(
            width: mappedVisibleSize.width / cropCGRect.width,
            height: mappedVisibleSize.height / cropCGRect.height
        )
        return Int(
            ceil(
                max(
                    max(
                        fullImagePreviewSize.width,
                        fullImagePreviewSize.height
                    ),
                    64
                )
            )
        )
    }

    private func loadAssetPreviewImage(
        for itemRecord: BoardImageItemRecord,
        assetsDirectoryURL: URL,
        animatedImagePreviewMode: CanvasAnimatedImagePreviewMode,
        maxPixelSize: Int
    ) throws -> CGImage {
        try mediaPosterImageResolver.resolvePreviewImage(
            for: itemRecord,
            assetsDirectoryURL: assetsDirectoryURL,
            animatedImagePreviewMode: animatedImagePreviewMode,
            maxPixelSize: maxPixelSize
        )
    }

    private func orderedItemRecords(
        from itemRecords: [BoardItemRecord]
    ) -> [BoardItemRecord] {
        itemRecords.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
    }

    private func bitmapReplayRect(
        fromPreviewRect previewRect: CGRect,
        pixelSize: CGSize
    ) -> CGRect {
        let standardizedPreviewRect = previewRect.standardized
        return CGRect(
            x: standardizedPreviewRect.minX,
            y: pixelSize.height - standardizedPreviewRect.maxY,
            width: standardizedPreviewRect.width,
            height: standardizedPreviewRect.height
        ).standardized
    }

    private func imageGeometry(
        for image: CGImage,
        displayWorldRect: CGRect,
        contentInset: CGFloat
    ) -> CanvasMiniMapViewGeometry? {
        CanvasMiniMapViewGeometry(
            displayWorldRect: displayWorldRect,
            viewBounds: CGRect(
                origin: .zero,
                size: CGSize(
                    width: CGFloat(image.width),
                    height: CGFloat(image.height)
                )
            ),
            contentInset: contentInset
        )
    }
}

private func makeTraceContext(
    mode: String,
    boardID: UUID?,
    itemRecords: [BoardItemRecord]
) -> BoardThumbnailTraceContext {
    BoardThumbnailTraceContext(
        mode: mode,
        boardID: boardID,
        documentOrderByID: Dictionary(
            uniqueKeysWithValues: itemRecords.enumerated().map { documentOrder, item in
                (item.id, documentOrder)
            }
        )
    )
}

func logBoardThumbnailTraceImageRegions(
    phase: String,
    mode: String,
    boardID: UUID?,
    previewSeed: BoardPreviewSeed,
    targetPixelSize: CGSize,
    contentInset: CGFloat,
    image: CGImage
) {
    let normalizedTargetPixelSize = CGSize(
        width: max(targetPixelSize.width.rounded(.up), 1),
        height: max(targetPixelSize.height.rounded(.up), 1)
    )
    let snapshot = BoardGeometryPreviewBuilder().makeSnapshot(from: previewSeed)
    guard
        let geometry = CanvasMiniMapViewGeometry(
            displayWorldRect: snapshot.displayWorldRect,
            viewBounds: CGRect(origin: .zero, size: normalizedTargetPixelSize),
            contentInset: contentInset
        )
    else {
        return
    }

    let traceContext = BoardThumbnailTraceContext(
        mode: mode,
        boardID: boardID,
        documentOrderByID: Dictionary(
            uniqueKeysWithValues: previewSeed.nodes.enumerated().map { index, node in
                (node.id, index)
            }
        )
    )
    print(
        "[BoardList][ThumbnailTrace][ImageSnapshot] " +
            "phase=\(phase) " +
            "mode=\(mode) " +
            "boardID=\(boardID?.uuidString ?? "nil") " +
            "targetPixelSize=\(describeBoardThumbnailSize(normalizedTargetPixelSize)) " +
            "contentInset=\(formatBoardThumbnailValue(contentInset)) " +
            "signature=\(BoardThumbnailImageSignature.describe(image))"
    )
    logNodeRegionSamples(
        phase: phase,
        traceContext: traceContext,
        nodes: previewSeed.nodes,
        geometry: geometry,
        image: image
    )
}

private func logRenderSurface(
    traceContext: BoardThumbnailTraceContext,
    previewSeed: BoardPreviewSeed,
    targetPixelSize: CGSize,
    contentInset: CGFloat,
    geometry: CanvasMiniMapViewGeometry,
    context: CGContext
) {
    print(
        "[BoardList][ThumbnailTrace][RenderSurface] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "targetPixelSize=\(describeBoardThumbnailSize(targetPixelSize)) " +
            "contentInset=\(formatBoardThumbnailValue(contentInset)) " +
            "boardWorldRect=\(describeBoardThumbnailRect(previewSeed.boardWorldRect)) " +
            "displayWorldRect=\(describeBoardThumbnailRect(geometry.displayWorldRect)) " +
            "contentRect=\(describeBoardThumbnailRect(geometry.contentRect)) " +
            "scale=\(formatBoardThumbnailValue(geometry.scale)) " +
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
    )
}

private func logPersistedReplayDraw(
    traceContext: BoardThumbnailTraceContext,
    previewRect: CGRect,
    bitmapReplayRect: CGRect,
    persistedThumbnail: CGImage,
    context: CGContext
) {
    print(
        "[BoardList][ThumbnailTrace][PersistedReplayDraw] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "previewRect=\(describeBoardThumbnailRect(previewRect)) " +
            "bitmapReplayRect=\(describeBoardThumbnailRect(bitmapReplayRect)) " +
            "persistedSignature=\(BoardThumbnailImageSignature.describe(persistedThumbnail)) " +
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
    )
}

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
            "itemID=\(itemID.uuidString) " +
            "documentOrder=\(documentOrder.map(String.init) ?? "nil") " +
            "renderOrder=\(renderOrder) " +
            "worldCenter=\(describeBoardThumbnailPoint(worldCenter)) " +
            "worldCenterY=\(formatBoardThumbnailValue(worldCenter.y)) " +
            "mappedCenter=\(describeBoardThumbnailPoint(mappedCenter)) " +
            "mappedCenterY=\(formatBoardThumbnailValue(mappedCenter.y)) " +
            "visibleSize=\(describeBoardThumbnailSize(visibleSize)) " +
            "cropRect=\(describeBoardThumbnailRect(cropRect)) " +
            "previewVisibleRect=\(describeBoardThumbnailRect(previewVisibleRect)) " +
            "previewFullImageRect=\(describeBoardThumbnailRect(previewFullImageRect)) " +
            "rotationDeg=\(formatBoardThumbnailValue(rotationRadians * 180 / .pi)) " +
            "imageSignature=\(BoardThumbnailImageSignature.describe(image)) " +
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
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
    let bitmapVisibleRect = bitmapRectForRenderedPreview(
        previewRect: previewVisibleRect,
        image: renderedImage
    )
    print(
        "[BoardList][ThumbnailTrace][PosterDrawResult] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "kind=\(describeBoardThumbnailNodeKind(kind)) " +
            "itemID=\(itemID.uuidString) " +
            "documentOrder=\(documentOrder.map(String.init) ?? "nil") " +
            "renderOrder=\(renderOrder) " +
            "previewVisibleRect=\(describeBoardThumbnailRect(previewVisibleRect)) " +
            "renderedRegionSignature=\(describeBoardThumbnailRegionSignature(renderedImage, bitmapRect: bitmapVisibleRect))"
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
        let previewRect = geometry.worldToMiniMap(node.worldQuad)
            .boundingRect
            .standardized
        let bitmapRect = bitmapRectForRenderedPreview(
            previewRect: previewRect,
            image: image
        )
        print(
            "[BoardList][ThumbnailTrace][NodeRegion] " +
                "phase=\(phase) " +
                "mode=\(traceContext.mode) " +
                "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
                "itemID=\(node.id.uuidString) " +
                "previewRect=\(describeBoardThumbnailRect(previewRect)) " +
                "regionSignature=\(describeBoardThumbnailRegionSignature(image, bitmapRect: bitmapRect))"
        )
    }
}

private func logTextDraw(
    traceContext: BoardThumbnailTraceContext,
    itemID: UUID,
    documentOrder: Int?,
    renderOrder: Int,
    worldCenter: CGPoint,
    mappedCenter: CGPoint,
    visibleSize: CGSize,
    previewTextRect: CGRect,
    rotationRadians: CGFloat,
    context: CGContext
) {
    print(
        "[BoardList][ThumbnailTrace][TextDraw] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "itemID=\(itemID.uuidString) " +
            "documentOrder=\(documentOrder.map(String.init) ?? "nil") " +
            "renderOrder=\(renderOrder) " +
            "worldCenter=\(describeBoardThumbnailPoint(worldCenter)) " +
            "worldCenterY=\(formatBoardThumbnailValue(worldCenter.y)) " +
            "mappedCenter=\(describeBoardThumbnailPoint(mappedCenter)) " +
            "mappedCenterY=\(formatBoardThumbnailValue(mappedCenter.y)) " +
            "visibleSize=\(describeBoardThumbnailSize(visibleSize)) " +
            "previewTextRect=\(describeBoardThumbnailRect(previewTextRect)) " +
            "rotationDeg=\(formatBoardThumbnailValue(rotationRadians * 180 / .pi)) " +
            "contextCTM=\(describeBoardThumbnailTransform(context.ctm))"
    )
}

private func logRenderedImage(
    traceContext: BoardThumbnailTraceContext,
    image: CGImage
) {
    print(
        "[BoardList][ThumbnailTrace][RenderedImage] " +
            "mode=\(traceContext.mode) " +
            "boardID=\(traceContext.boardID?.uuidString ?? "nil") " +
            "signature=\(BoardThumbnailImageSignature.describe(image))"
    )
}

private func bitmapRectForRenderedPreview(
    previewRect: CGRect,
    image: CGImage
) -> CGRect {
    let standardizedPreviewRect = previewRect.standardized
    return CGRect(
        x: standardizedPreviewRect.minX,
        y: CGFloat(image.height) - standardizedPreviewRect.maxY,
        width: standardizedPreviewRect.width,
        height: standardizedPreviewRect.height
    ).standardized
}

private func describeBoardThumbnailRegionSignature(
    _ image: CGImage,
    bitmapRect: CGRect
) -> String {
    let imageBounds = CGRect(
        x: 0,
        y: 0,
        width: CGFloat(image.width),
        height: CGFloat(image.height)
    )
    let clampedBitmapRect = bitmapRect.standardized.intersection(imageBounds)
    guard
        clampedBitmapRect.width > 0,
        clampedBitmapRect.height > 0
    else {
        return
            "bitmapRect=\(describeBoardThumbnailRect(bitmapRect.standardized)) " +
            "sampleGrid=empty"
    }

    guard
        let normalizedRegionImage = makeNormalizedRegionImage(
            from: image,
            bitmapRect: clampedBitmapRect
        )
    else {
        return
            "bitmapRect=\(describeBoardThumbnailRect(clampedBitmapRect)) " +
            "sampleGrid=unavailable"
    }

    return
        "bitmapRect=\(describeBoardThumbnailRect(clampedBitmapRect)) " +
        BoardThumbnailImageSignature.describe(normalizedRegionImage)
}

private func makeNormalizedRegionImage(
    from image: CGImage,
    bitmapRect: CGRect,
    samplePixelSize: CGSize = CGSize(width: 24, height: 24)
) -> CGImage? {
    let width = max(Int(samplePixelSize.width), 1)
    let height = max(Int(samplePixelSize.height), 1)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }

    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    else {
        return nil
    }

    context.interpolationQuality = .high
    let scaleX = samplePixelSize.width / bitmapRect.width
    let scaleY = samplePixelSize.height / bitmapRect.height
    context.scaleBy(x: scaleX, y: scaleY)
    context.draw(
        image,
        in: CGRect(
            x: -bitmapRect.minX,
            y: -bitmapRect.minY,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
    )
    return context.makeImage()
}

private func describeBoardThumbnailTransform(_ transform: CGAffineTransform) -> String {
    "[a=\(formatBoardThumbnailValue(transform.a)), " +
        "b=\(formatBoardThumbnailValue(transform.b)), " +
        "c=\(formatBoardThumbnailValue(transform.c)), " +
        "d=\(formatBoardThumbnailValue(transform.d)), " +
        "tx=\(formatBoardThumbnailValue(transform.tx)), " +
        "ty=\(formatBoardThumbnailValue(transform.ty))]"
}

private func describeBoardThumbnailNodeKind(_ kind: CanvasMiniMapNodeKind) -> String {
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

private func describeBoardThumbnailRect(_ rect: CGRect) -> String {
    "{{\(formatBoardThumbnailValue(rect.minX)), \(formatBoardThumbnailValue(rect.minY))}, {\(formatBoardThumbnailValue(rect.width)), \(formatBoardThumbnailValue(rect.height))}}"
}

private func describeBoardThumbnailPoint(_ point: CGPoint) -> String {
    "{\(formatBoardThumbnailValue(point.x)), \(formatBoardThumbnailValue(point.y))}"
}

private func describeBoardThumbnailSize(_ size: CGSize) -> String {
    "{\(formatBoardThumbnailValue(size.width)), \(formatBoardThumbnailValue(size.height))}"
}

private func formatBoardThumbnailValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
