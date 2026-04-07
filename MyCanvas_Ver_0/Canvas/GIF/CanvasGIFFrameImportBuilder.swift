import CoreGraphics
import Foundation
import ImageIO

enum CanvasGIFFrameImportBuilderError: LocalizedError {
    case invalidAnimatedGIFItem(itemID: UUID)
    case missingBoardIdentity
    case missingAnimatedImageSource(itemID: UUID)
    case invalidGIFData
    case emptyFrameSelection
    case frameIndexOutOfBounds(frameIndex: Int, frameCount: Int)
    case failedToDecodeFrame(frameIndex: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidAnimatedGIFItem(itemID):
            return "The selected item is not a valid animated GIF item: \(itemID.uuidString)"
        case .missingBoardIdentity:
            return "Unable to resolve the active board for GIF frame import."
        case let .missingAnimatedImageSource(itemID):
            return "The original animated GIF data is unavailable for board item \(itemID.uuidString)."
        case .invalidGIFData:
            return "The GIF data could not be decoded for frame import."
        case .emptyFrameSelection:
            return "No GIF frames are selected for import."
        case let .frameIndexOutOfBounds(frameIndex, frameCount):
            return "The selected GIF frame index \(frameIndex) is outside the valid range 0..<\(frameCount)."
        case let .failedToDecodeFrame(frameIndex):
            return "Unable to decode GIF frame \(frameIndex) for import."
        }
    }
}

enum CanvasGIFFrameImportBuilder {
    static let defaultSourceDescription = "gif-derived frames"

    static func makeImportRequest(
        from sourceItem: CanvasImageItem,
        gifData: Data,
        selectedFrameIndices: [Int],
        configuration: CanvasGIFFrameImportConfiguration = .current,
        sourceDescription: String = defaultSourceDescription
    ) throws -> CanvasImportRequest {
        guard sourceItem.isVideo == false, sourceItem.assetKind == .animatedGIF else {
            throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
                itemID: sourceItem.id
            )
        }

        guard let imageSource = CanvasGIFFrameService.makeImageSource(from: gifData) else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            throw CanvasGIFFrameImportBuilderError.invalidGIFData
        }

        let resolvedFrameIndices = try normalizedFrameIndices(
            selectedFrameIndices,
            frameCount: frameCount
        )
        let importedImages = try resolvedFrameIndices.map { frameIndex in
            try makeResolvedImportImage(
                frameIndex: frameIndex,
                imageSource: imageSource
            )
        }

        let boardPlacementGrid = configuration.boardPlacementGrid
        let presentationTemplate = CanvasImportPresentationTemplate(
            size: sourceItem.size,
            cropRectNormalized: sourceItem.cropRectNormalized,
            rotationPolicy: .fixed(0)
        )
        return CanvasImportRequest(
            images: importedImages,
            placement: .worldPoint(
                gridOrigin(
                    for: sourceItem,
                    presentationSize: presentationTemplate.size,
                    gridConfiguration: boardPlacementGrid
                )
            ),
            layout: .grid(
                columns: boardPlacementGrid.columns,
                horizontalSpacing: boardPlacementGrid.horizontalSpacing,
                verticalSpacing: boardPlacementGrid.verticalSpacing
            ),
            presentationTemplate: presentationTemplate,
            sourceDescription: sourceDescription
        )
    }

    private static func normalizedFrameIndices(
        _ frameIndices: [Int],
        frameCount: Int
    ) throws -> [Int] {
        let uniqueFrameIndices = Array(Set(frameIndices)).sorted()
        guard uniqueFrameIndices.isEmpty == false else {
            throw CanvasGIFFrameImportBuilderError.emptyFrameSelection
        }

        if let invalidFrameIndex = uniqueFrameIndices.first(where: {
            $0 < 0 || $0 >= frameCount
        }) {
            throw CanvasGIFFrameImportBuilderError.frameIndexOutOfBounds(
                frameIndex: invalidFrameIndex,
                frameCount: frameCount
            )
        }

        return uniqueFrameIndices
    }

    private static func makeResolvedImportImage(
        frameIndex: Int,
        imageSource: CGImageSource
    ) throws -> CanvasResolvedImportImage {
        guard let cgImage = CanvasGIFFrameService.decodeFrame(
            at: frameIndex,
            from: imageSource
        ) else {
            throw CanvasGIFFrameImportBuilderError.failedToDecodeFrame(
                frameIndex: frameIndex
            )
        }

        return CanvasResolvedImportImage(
            cgImage: cgImage,
            assetKind: .staticImage,
            importedSource: nil,
            animatedMetadata: nil,
            logicalPixelSize: CGSize(
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }

    private static func gridOrigin(
        for sourceItem: CanvasImageItem,
        presentationSize: CGSize,
        gridConfiguration: CanvasGIFFrameImportGridConfiguration
    ) -> CGPoint {
        let sourceBounds = sourceItem.worldBounds
        return CGPoint(
            x: sourceBounds.minX
                + gridConfiguration.contentInsets.leading
                + presentationSize.width / 2,
            y: sourceBounds.maxY
                + gridConfiguration.contentInsets.top
                + presentationSize.height / 2
        )
    }
}
