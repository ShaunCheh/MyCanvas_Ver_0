import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidBoardImageAsset(filename: String)
    case invalidRuntimeImageAsset(itemID: UUID)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidBitmapContext:
            return "The thumbnail bitmap context could not be created."
        case let .invalidBoardImageAsset(filename):
            return "The board thumbnail asset could not be decoded: \(filename)"
        case let .invalidRuntimeImageAsset(itemID):
            return "The runtime image asset for board item \(itemID.uuidString) is missing."
        case .cancelled:
            return "The thumbnail request was cancelled."
        }
    }
}

final class BoardThumbnailRenderer {
    private let geometryPreviewBuilder: BoardGeometryPreviewBuilder

    init(
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder()
    ) {
        self.geometryPreviewBuilder = geometryPreviewBuilder
    }

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
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
        let targetPixelSize = BoardPersistedThumbnailStore.pixelSize(
            forDisplayWorldRect: snapshot.displayWorldRect,
            maximumLongestSide: maximumLongestSide
        )
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            return nil
        }

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

    func renderThumbnail(
        fromPersistedThumbnail persistedThumbnail: CGImage,
        previewSeed: BoardPreviewSeed,
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

        prepareContext(
            context,
            pixelSize: normalizedTargetPixelSize
        )
        try cancellationCheck()
        context.draw(persistedThumbnail, in: geometry.contentRect)
        try cancellationCheck()
        return context.makeImage()
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

        prepareContext(
            context,
            pixelSize: normalizedTargetPixelSize
        )

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

    private func prepareContext(
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

        // Flip into a top-left coordinate space so thumbnail drawing matches the
        // preview view and the canvas layer pipeline.
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: 1, y: -1)
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

    private func drawLoadedImage(
        _ image: CGImage,
        for itemRecord: BoardImageItemRecord,
        geometry: CanvasMiniMapViewGeometry,
        in context: CGContext
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

        let mappedVisibleSize = CGSize(
            width: visibleSize.width * geometry.scale,
            height: visibleSize.height * geometry.scale
        )
        guard mappedVisibleSize.width > 0, mappedVisibleSize.height > 0 else {
            return
        }

        let fullImagePreviewSize = CGSize(
            width: mappedVisibleSize.width / cropCGRect.width,
            height: mappedVisibleSize.height / cropCGRect.height
        )
        let mappedCenter = geometry.worldToMiniMap(itemRecord.center.cgPoint)
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
        let rotationRadians = normalizedCanvasAngle(
            CGFloat(itemRecord.rotationRadians ?? 0)
        )

        context.saveGState()
        context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
        context.rotate(by: rotationRadians)
        context.clip(to: visibleRect)
        context.draw(image, in: fullImageRect)
        context.restoreGState()
    }

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

    private func loadAssetImage(
        for itemRecord: BoardImageItemRecord,
        assetsDirectoryURL: URL,
        maxPixelSize: Int
    ) throws -> CGImage {
        let assetURL = assetsDirectoryURL.appendingPathComponent(itemRecord.assetFilename)
        let assetData = try CoordinatedFileIO.readData(at: assetURL)
        guard
            let imageSource = CGImageSourceCreateWithData(assetData as CFData, nil)
        else {
            throw BoardThumbnailRendererError.invalidBoardImageAsset(
                filename: itemRecord.assetFilename
            )
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) {
            return thumbnail
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard
            let image = CGImageSourceCreateImageAtIndex(
                imageSource,
                0,
                imageOptions as CFDictionary
            )
        else {
            throw BoardThumbnailRendererError.invalidBoardImageAsset(
                filename: itemRecord.assetFilename
            )
        }

        return image
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
}
