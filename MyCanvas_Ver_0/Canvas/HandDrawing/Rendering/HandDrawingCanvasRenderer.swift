import CoreGraphics
import Foundation

enum HandDrawingCanvasRendererError: LocalizedError {
    case failedToCreateBitmapContext(width: Int, height: Int)
    case failedToAllocateBitmapBuffer(width: Int, height: Int)
    case failedToCreateCanvasImage
    case failedToAccessBitmapData
    case failedToAllocateImageBuffer
    case failedToCreateImageDataProvider

    var errorDescription: String? {
        switch self {
        case let .failedToCreateBitmapContext(width, height):
            return "Failed to create hand drawing canvas bitmap context: \(width)x\(height)."
        case let .failedToAllocateBitmapBuffer(width, height):
            return "Failed to allocate hand drawing canvas bitmap buffer: \(width)x\(height)."
        case .failedToCreateCanvasImage:
            return "Failed to create the hand drawing canvas image."
        case .failedToAccessBitmapData:
            return "Failed to access the hand drawing canvas bitmap data."
        case .failedToAllocateImageBuffer:
            return "Failed to allocate the hand drawing canvas image buffer."
        case .failedToCreateImageDataProvider:
            return "Failed to create the hand drawing canvas image data provider."
        }
    }
}

final class HandDrawingCanvasRenderer {
    private let backgroundColor: HandDrawingColor?
    private var paperSize: CGSize
    private var bitmapBuffer: UnsafeMutableRawPointer
    private var bitmapContext: CGContext

    init(
        paperSize: CGSize,
        backgroundColor: HandDrawingColor? = nil
    ) throws {
        self.backgroundColor = backgroundColor
        self.paperSize = paperSize
        let resolvedStorage = try Self.makeBitmapStorage(for: paperSize)
        bitmapBuffer = resolvedStorage.buffer
        bitmapContext = resolvedStorage.context
        clear(region: CGRect(origin: .zero, size: paperSize))
    }

    deinit {
        free(bitmapBuffer)
    }

    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect? = nil
    ) throws -> CGImage {
        try render(
            request: HandDrawingCommittedCanvasRenderRequest(
                document: document,
                dirtyRegion: dirtyRegion
            )
        )
    }

    func render(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws -> CGImage {
        let document = request.document
        if paperSize != document.paper.size {
            let oldBuffer = bitmapBuffer
            paperSize = document.paper.size
            let resolvedStorage = try Self.makeBitmapStorage(
                for: document.paper.size
            )
            bitmapBuffer = resolvedStorage.buffer
            bitmapContext = resolvedStorage.context
            free(oldBuffer)
            clear(region: document.paperBounds)
        }

        let renderRegion = request.renderRegion
        clear(region: renderRegion)
        bitmapContext.saveGState()
        bitmapContext.addRect(renderRegion)
        bitmapContext.clip()

        for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
            guard
                let strokeBounds = stroke.bounds,
                strokeBounds.intersects(renderRegion)
            else {
                continue
            }
            HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
        }
        bitmapContext.restoreGState()

        return try Self.makeOwnedImage(from: bitmapContext)
    }

    private func clear(region: CGRect) {
        guard region.isNull == false, region.isEmpty == false else {
            return
        }
        bitmapContext.saveGState()
        bitmapContext.addRect(region)
        bitmapContext.clip()
        bitmapContext.clear(region)
        if let backgroundColor {
            bitmapContext.setFillColor(backgroundColor.cgColor)
            bitmapContext.fill(region)
        }
        bitmapContext.restoreGState()
    }

    private static func makeBitmapStorage(
        for size: CGSize
    ) throws -> (buffer: UnsafeMutableRawPointer, context: CGContext) {
        let width = max(Int(ceil(size.width)), 1)
        let height = max(Int(ceil(size.height)), 1)
        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        guard let buffer = calloc(byteCount, 1) else {
            throw HandDrawingCanvasRendererError.failedToAllocateBitmapBuffer(
                width: width,
                height: height
            )
        }
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard
            let context = CGContext(
                data: buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else {
            free(buffer)
            throw HandDrawingCanvasRendererError.failedToCreateBitmapContext(
                width: width,
                height: height
            )
        }
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        configureDisplayCoordinateSpace(
            for: context,
            height: CGFloat(height)
        )
        return (buffer, context)
    }

    private static func configureDisplayCoordinateSpace(
        for context: CGContext,
        height: CGFloat
    ) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }

    private static func makeOwnedImage(
        from context: CGContext
    ) throws -> CGImage {
        guard let bitmapData = context.data else {
            throw HandDrawingCanvasRendererError.failedToAccessBitmapData
        }
        let bytesPerRow = context.bytesPerRow
        let width = context.width
        let height = context.height
        let byteCount = bytesPerRow * height
        guard let copiedBuffer = malloc(byteCount) else {
            throw HandDrawingCanvasRendererError.failedToAllocateImageBuffer
        }
        memcpy(copiedBuffer, bitmapData, byteCount)
        let releaseData: CGDataProviderReleaseDataCallback = { _, data, _ in
            free(UnsafeMutableRawPointer(mutating: data))
        }
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: copiedBuffer,
            size: byteCount,
            releaseData: releaseData
        ) else {
            free(copiedBuffer)
            throw HandDrawingCanvasRendererError.failedToCreateImageDataProvider
        }
        guard let ownedImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: context.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: context.bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw HandDrawingCanvasRendererError.failedToCreateCanvasImage
        }
        return ownedImage
    }
}
