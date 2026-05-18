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

    private static func drawStrokeInk(
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

    private static func drawDisk(
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
