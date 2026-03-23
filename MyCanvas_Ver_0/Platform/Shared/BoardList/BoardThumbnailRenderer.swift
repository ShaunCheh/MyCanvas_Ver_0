import CoreGraphics
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
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: previewSeed)
        let targetPixelSize = BoardPersistedThumbnailStore.pixelSize(
            forDisplayWorldRect: snapshot.displayWorldRect,
            maximumLongestSide: maximumLongestSide
        )
        guard targetPixelSize.width > 0, targetPixelSize.height > 0 else {
            return nil
        }

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
        from itemRecords: [BoardImageItemRecord]
    ) -> [BoardImageItemRecord] {
        itemRecords.sorted { lhs, rhs in
            if lhs.zIndex == rhs.zIndex {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.zIndex < rhs.zIndex
        }
    }
}
