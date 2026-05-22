import CoreGraphics
import Foundation

enum HandDrawingStrokeRasterizer {
    static func draw(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        drawStrokeInk(stroke, in: context)
        applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: context)
    }

    static func draw(
        _ resolvedSamples: [HandDrawingResolvedBrushSample],
        color: HandDrawingColor,
        in context: CGContext
    ) {
        guard resolvedSamples.isEmpty == false else {
            return
        }
        context.setFillColor(color.cgColor)
        for sample in resolvedSamples {
            drawStamp(sample, in: context)
        }
    }

    private static func drawStrokeInk(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        let resolvedSamples = HandDrawingBrushDynamics.resolvedStamps(
            for: stroke
        )
        guard resolvedSamples.isEmpty == false else {
            return
        }
        draw(
            resolvedSamples,
            color: stroke.brush.color,
            in: context
        )
    }

    private static func applyEraseMask(
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

    private static func drawStamp(
        _ sample: HandDrawingResolvedBrushSample,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: -sample.majorRadius,
            y: -sample.minorRadius,
            width: sample.majorRadius * 2,
            height: sample.minorRadius * 2
        )
        context.saveGState()
        context.setAlpha(sample.opacity)
        context.translateBy(x: sample.point.x, y: sample.point.y)
        context.rotate(by: sample.rotationRadians)
        context.fillEllipse(in: rect)
        context.restoreGState()
    }

    private static func clearDisk(
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
}
