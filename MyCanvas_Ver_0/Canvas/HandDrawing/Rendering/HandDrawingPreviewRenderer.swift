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
    private let graphRenderer = HandDrawingCPURenderGraphRenderer()

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

        let renderGraph = HandDrawingRenderGraphBuilder.graph(
            for: document,
            paperTransform: CGAffineTransform(
                scaleX: resolvedScale,
                y: resolvedScale
            )
        )
        try graphRenderer.draw(
            renderGraph,
            in: compositeContext,
            canvasPixelSize: CGSize(
                width: pixelWidth,
                height: pixelHeight
            )
        )

        guard let image = compositeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        return image
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
