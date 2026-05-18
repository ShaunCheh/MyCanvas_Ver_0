import CoreGraphics
import Foundation

enum HandDrawingPreviewRendererError: LocalizedError {
    case failedToCreateBitmapContext(width: Int, height: Int)
    case failedToCreatePreviewImage

    var errorDescription: String? {
        switch self {
        case let .failedToCreateBitmapContext(width, height):
            return "Failed to create hand drawing bitmap context: \(width)x\(height)."
        case .failedToCreatePreviewImage:
            return "Failed to create the hand drawing preview image."
        }
    }
}

struct HandDrawingPreviewRenderer {
    func renderPreviewImage(
        for document: HandDrawingDocument,
        scale: CGFloat = 1,
        backgroundColor: HandDrawingColor? = nil
    ) throws -> CGImage {
        let resolvedScale = max(scale, 0.25)
        let paperSize = document.paper.size
        let pixelWidth = max(Int(ceil(paperSize.width * resolvedScale)), 1)
        let pixelHeight = max(Int(ceil(paperSize.height * resolvedScale)), 1)
        let compositeContext = try makeBitmapContext(
            width: pixelWidth,
            height: pixelHeight
        )
        configureDisplayCoordinateSpace(
            for: compositeContext,
            height: CGFloat(pixelHeight)
        )
        let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        if let backgroundColor {
            compositeContext.setFillColor(backgroundColor.cgColor)
            compositeContext.fill(pixelRect)
        }

        for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
            try drawStroke(
                stroke,
                into: compositeContext,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: resolvedScale
            )
        }

        guard let image = compositeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        return image
    }

    private func drawStroke(
        _ stroke: HandDrawingStroke,
        into compositeContext: CGContext,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat
    ) throws {
        let strokeContext = try makeBitmapContext(
            width: pixelWidth,
            height: pixelHeight
        )
        strokeContext.scaleBy(x: scale, y: scale)
        HandDrawingStrokeRasterizer.draw(stroke, in: strokeContext)
        guard let strokeImage = strokeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        compositeContext.draw(
            strokeImage,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
    }

    private func makeBitmapContext(
        width: Int,
        height: Int
    ) throws -> CGContext {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw HandDrawingPreviewRendererError.failedToCreateBitmapContext(
                width: width,
                height: height
            )
        }
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        return context
    }

    private func configureDisplayCoordinateSpace(
        for context: CGContext,
        height: CGFloat
    ) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }
}
