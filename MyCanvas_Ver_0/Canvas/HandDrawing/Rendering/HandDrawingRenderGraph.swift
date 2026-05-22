import CoreGraphics
import Foundation

struct HandDrawingResolvedEraseSample: Equatable {
    let point: CGPoint
    let radius: CGFloat
    let opacity: CGFloat

    var bounds: CGRect {
        CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
}

struct HandDrawingResolvedErasePath: Equatable {
    let pathID: UUID
    let samples: [HandDrawingResolvedEraseSample]

    var bounds: CGRect? {
        samples.reduce(nil) { partialResult, sample in
            partialResult?.union(sample.bounds) ?? sample.bounds
        }
    }
}

struct HandDrawingStrokeRenderSnapshot: Equatable {
    let strokeID: UUID?
    let color: HandDrawingColor
    let resolvedStamps: [HandDrawingResolvedBrushSample]
    let resolvedErasePaths: [HandDrawingResolvedErasePath]
    let bounds: CGRect?

    var isEmpty: Bool {
        resolvedStamps.isEmpty && resolvedErasePaths.allSatisfy(\.samples.isEmpty)
    }
}

struct HandDrawingRenderGraphLayer: Equatable {
    let layerID: UUID
    let strokeSnapshots: [HandDrawingStrokeRenderSnapshot]
}

struct HandDrawingRenderGraph: Equatable {
    let paperSize: CGSize
    let paperTransform: CGAffineTransform
    let renderRegion: CGRect?
    let layers: [HandDrawingRenderGraphLayer]

    var paperBounds: CGRect {
        CGRect(origin: .zero, size: paperSize)
    }

    var renderedStrokeSnapshotsInOrder: [HandDrawingStrokeRenderSnapshot] {
        layers.flatMap(\.strokeSnapshots)
    }
}

enum HandDrawingRenderGraphBuilder {
    static func graph(
        for document: HandDrawingDocument,
        renderRegion: CGRect? = nil,
        paperTransform: CGAffineTransform = .identity
    ) -> HandDrawingRenderGraph {
        let layers = document.visibleLayersInRenderOrder.map { layer in
            HandDrawingRenderGraphLayer(
                layerID: layer.id,
                strokeSnapshots: layer.strokes.compactMap { stroke in
                    let snapshot = strokeSnapshot(for: stroke)
                    guard snapshot.isEmpty == false else {
                        return nil
                    }
                    if let renderRegion,
                       let bounds = snapshot.bounds,
                       bounds.intersects(renderRegion) == false
                    {
                        return nil
                    }
                    return snapshot
                }
            )
        }
        return HandDrawingRenderGraph(
            paperSize: document.paper.size,
            paperTransform: paperTransform,
            renderRegion: renderRegion,
            layers: layers
        )
    }

    static func strokeSnapshot(
        for stroke: HandDrawingStroke
    ) -> HandDrawingStrokeRenderSnapshot {
        let resolvedStamps = HandDrawingBrushDynamics.resolvedStamps(for: stroke)
        let resolvedErasePaths = resolvedErasePaths(for: stroke)
        return strokeSnapshot(
            strokeID: stroke.id,
            brush: stroke.brush,
            resolvedStamps: resolvedStamps,
            resolvedErasePaths: resolvedErasePaths
        )
    }

    static func strokeSnapshot(
        strokeID: UUID? = nil,
        brush: HandDrawingBrushStyle,
        resolvedStamps: [HandDrawingResolvedBrushSample],
        resolvedErasePaths: [HandDrawingResolvedErasePath] = [],
        bounds: CGRect? = nil
    ) -> HandDrawingStrokeRenderSnapshot {
        HandDrawingStrokeRenderSnapshot(
            strokeID: strokeID,
            color: brush.color,
            resolvedStamps: resolvedStamps,
            resolvedErasePaths: resolvedErasePaths,
            bounds: bounds ?? unionBounds(
                resolvedStamps: resolvedStamps,
                resolvedErasePaths: resolvedErasePaths
            )
        )
    }

    private static func resolvedErasePaths(
        for stroke: HandDrawingStroke
    ) -> [HandDrawingResolvedErasePath] {
        stroke.eraseMask.map { erasePath in
            HandDrawingResolvedErasePath(
                pathID: erasePath.id,
                samples: erasePath.samplePoints.map { sample in
                    HandDrawingResolvedEraseSample(
                        point: stroke.transform.apply(to: sample.cgPoint),
                        radius: sample.resolvedRadius,
                        opacity: CGFloat(sample.opacity)
                    )
                }
            )
        }
    }

    private static func unionBounds(
        resolvedStamps: [HandDrawingResolvedBrushSample],
        resolvedErasePaths: [HandDrawingResolvedErasePath]
    ) -> CGRect? {
        let stampBounds = resolvedStamps.reduce(nil) { partialResult, stamp in
            partialResult?.union(stamp.axisAlignedBounds) ?? stamp.axisAlignedBounds
        }
        let eraseBounds = resolvedErasePaths.compactMap(\.bounds).reduce(nil) {
            partialResult,
            bounds in
            partialResult?.union(bounds) ?? bounds
        }
        if let stampBounds, let eraseBounds {
            return stampBounds.union(eraseBounds)
        }
        return stampBounds ?? eraseBounds
    }
}

enum HandDrawingCPURenderGraphRendererError: LocalizedError {
    case failedToCreateBitmapContext(width: Int, height: Int)
    case failedToCreateStrokeImage

    var errorDescription: String? {
        switch self {
        case let .failedToCreateBitmapContext(width, height):
            return "Failed to create the hand drawing render graph bitmap context: \(width)x\(height)."
        case .failedToCreateStrokeImage:
            return "Failed to create the hand drawing render graph stroke image."
        }
    }
}

struct HandDrawingCPURenderGraphRenderer {
    func draw(
        _ graph: HandDrawingRenderGraph,
        in compositeContext: CGContext,
        canvasPixelSize: CGSize
    ) throws {
        for snapshot in graph.renderedStrokeSnapshotsInOrder {
            try draw(
                snapshot,
                paperTransform: graph.paperTransform,
                in: compositeContext,
                canvasPixelSize: canvasPixelSize
            )
        }
    }

    func draw(
        _ snapshot: HandDrawingStrokeRenderSnapshot,
        paperTransform: CGAffineTransform = .identity,
        in compositeContext: CGContext,
        canvasPixelSize: CGSize
    ) throws {
        let strokeImage = try makeImage(
            for: snapshot,
            paperTransform: paperTransform,
            canvasPixelSize: canvasPixelSize
        )
        compositeContext.draw(
            strokeImage,
            in: CGRect(origin: .zero, size: canvasPixelSize)
        )
    }

    func makeImage(
        for snapshot: HandDrawingStrokeRenderSnapshot,
        paperTransform: CGAffineTransform = .identity,
        canvasPixelSize: CGSize
    ) throws -> CGImage {
        let width = max(Int(ceil(canvasPixelSize.width)), 1)
        let height = max(Int(ceil(canvasPixelSize.height)), 1)
        let strokeContext = try makeBitmapContext(width: width, height: height)
        strokeContext.concatenate(paperTransform)
        HandDrawingStrokeRasterizer.draw(snapshot, in: strokeContext)
        guard let strokeImage = strokeContext.makeImage() else {
            throw HandDrawingCPURenderGraphRendererError.failedToCreateStrokeImage
        }
        return strokeImage
    }

    private func makeBitmapContext(
        width: Int,
        height: Int
    ) throws -> CGContext {
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo.rawValue
            )
        else {
            throw HandDrawingCPURenderGraphRendererError.failedToCreateBitmapContext(
                width: width,
                height: height
            )
        }
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        return context
    }
}
