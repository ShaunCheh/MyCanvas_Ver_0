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
        let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        if let backgroundColor {
            compositeContext.setFillColor(backgroundColor.cgColor)
            compositeContext.fill(pixelRect)
        }

        for stroke in document.strokes where stroke.isEmpty == false {
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
        drawStrokeInk(stroke, in: strokeContext)
        applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: strokeContext)
        guard let strokeImage = strokeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        compositeContext.draw(
            strokeImage,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
    }

    private func drawStrokeInk(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        let points = stroke.transformedSamplePoints
        guard let firstPoint = points.first else {
            return
        }

        let resolvedColor = stroke.brush.color
            .withMultipliedAlpha(stroke.brush.opacity)
            .cgColor
        context.setStrokeColor(resolvedColor)
        context.setFillColor(resolvedColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if points.count == 1 {
            drawDisk(
                at: firstPoint,
                radius: stroke.radiusForSample(at: 0),
                in: context
            )
            return
        }

        for index in 0..<points.count {
            drawDisk(
                at: points[index],
                radius: stroke.radiusForSample(at: index),
                in: context
            )
        }

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let point = points[index]
            let lineWidth = stroke.radiusForSample(at: index - 1)
                + stroke.radiusForSample(at: index)
            context.setLineWidth(max(lineWidth, 0.5))
            context.beginPath()
            context.move(to: previousPoint)
            context.addLine(to: point)
            context.strokePath()
        }
    }

    private func applyEraseMask(
        _ eraseMask: [HandDrawingErasePath],
        transform: HandDrawingStrokeTransform,
        in context: CGContext
    ) {
        guard eraseMask.isEmpty == false else {
            return
        }

        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for erasePath in eraseMask {
            let transformedSamples = erasePath.samplePoints.map { sample in
                (
                    point: transform.apply(to: sample.cgPoint),
                    radius: sample.resolvedRadius,
                    opacity: CGFloat(sample.opacity)
                )
            }
            guard let firstSample = transformedSamples.first else {
                continue
            }

            if transformedSamples.count == 1 {
                context.setAlpha(firstSample.opacity)
                clearDisk(
                    at: firstSample.point,
                    radius: firstSample.radius,
                    in: context
                )
                continue
            }

            for index in 0..<transformedSamples.count {
                let sample = transformedSamples[index]
                context.setAlpha(sample.opacity)
                clearDisk(
                    at: sample.point,
                    radius: sample.radius,
                    in: context
                )
            }

            for index in 1..<transformedSamples.count {
                let previousSample = transformedSamples[index - 1]
                let sample = transformedSamples[index]
                context.setAlpha((previousSample.opacity + sample.opacity) / 2)
                context.setLineWidth(
                    max(previousSample.radius + sample.radius, 0.5)
                )
                context.beginPath()
                context.move(to: previousSample.point)
                context.addLine(to: sample.point)
                context.strokePath()
            }
        }

        context.restoreGState()
    }

    private func drawDisk(
        at point: CGPoint,
        radius: CGFloat,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fillEllipse(in: rect)
    }

    private func clearDisk(
        at point: CGPoint,
        radius: CGFloat,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fillEllipse(in: rect)
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
}
