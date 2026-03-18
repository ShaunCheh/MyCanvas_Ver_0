import CoreGraphics
import Foundation
import ImageIO

enum BoardThumbnailRendererError: LocalizedError {
    case invalidBitmapContext
    case invalidBoardImageAsset(filename: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidBitmapContext:
            return "The thumbnail bitmap context could not be created."
        case let .invalidBoardImageAsset(filename):
            return "The board thumbnail asset could not be decoded: \(filename)"
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
        guard item.document.items.isEmpty == false else {
            return nil
        }

        let snapshot = geometryPreviewBuilder.makeSnapshot(from: item.previewSeed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: CGRect(origin: .zero, size: targetPixelSize),
                contentInset: contentInset
            )
        else {
            return nil
        }

        let pixelWidth = max(Int(targetPixelSize.width.rounded(.up)), 1)
        let pixelHeight = max(Int(targetPixelSize.height.rounded(.up)), 1)
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw BoardThumbnailRendererError.invalidBitmapContext
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: pixelWidth,
                height: pixelHeight
            )
        )

        // Flip into a top-left coordinate space so thumbnail drawing matches the
        // preview view and the canvas layer pipeline.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)

        for itemRecord in orderedItemRecords(from: item.document.items) {
            try cancellationCheck()
            try drawItemRecord(
                itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                geometry: geometry,
                in: context,
                cancellationCheck: cancellationCheck
            )
        }

        try cancellationCheck()
        return context.makeImage()
    }

    private func drawItemRecord(
        _ itemRecord: BoardImageItemRecord,
        assetsDirectoryURL: URL,
        geometry: CanvasMiniMapViewGeometry,
        in context: CGContext,
        cancellationCheck: () throws -> Void
    ) throws {
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
        let decodeMaxPixelSize = Int(
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

        let image = try loadAssetImage(
            for: itemRecord,
            assetsDirectoryURL: assetsDirectoryURL,
            maxPixelSize: decodeMaxPixelSize
        )
        try cancellationCheck()

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
