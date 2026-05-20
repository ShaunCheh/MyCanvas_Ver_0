import CoreGraphics
import CoreText
import Foundation

protocol CanvasMarkdownBitmapRendering: AnyObject {
    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage?
}

final class CanvasMarkdownBitmapRenderer: CanvasMarkdownBitmapRendering {
    func render(
        layout: CanvasMarkdownLayoutResult,
        rasterScale: CGFloat
    ) -> CGImage? {
        guard
            rasterScale.isFinite,
            rasterScale > 0,
            layout.contentSize.width.isFinite,
            layout.contentSize.height.isFinite,
            layout.contentSize.width > 0,
            layout.contentSize.height > 0
        else {
            return nil
        }

        let pixelSize = CGSize(
            width: ceil(layout.contentSize.width * rasterScale),
            height: ceil(layout.contentSize.height * rasterScale)
        )
        guard
            pixelSize.width > 0,
            pixelSize.height > 0,
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
            return nil
        }

        prepareContext(
            context,
            layoutSize: layout.contentSize,
            pixelSize: pixelSize,
            rasterScale: rasterScale
        )
        drawDecorations(
            layout.decorations,
            in: context
        )
        drawAttributedText(
            layout.attributedText,
            in: CGRect(origin: .zero, size: layout.contentSize),
            context: context
        )
        return context.makeImage()
    }

    private func prepareContext(
        _ context: CGContext,
        layoutSize: CGSize,
        pixelSize: CGSize,
        rasterScale: CGFloat
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

        context.scaleBy(x: rasterScale, y: rasterScale)
        context.translateBy(x: 0, y: layoutSize.height)
        context.scaleBy(x: 1, y: -1)
    }

    private func drawDecorations(
        _ decorations: [CanvasMarkdownDecoration],
        in context: CGContext
    ) {
        for decoration in decorations {
            context.saveGState()
            context.setFillColor(cgColor(for: decoration.fillColor))
            let path = CGPath(
                roundedRect: decoration.rect,
                cornerWidth: decoration.cornerRadius,
                cornerHeight: decoration.cornerRadius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
    }

    private func drawAttributedText(
        _ attributedText: NSAttributedString,
        in rect: CGRect,
        context: CGContext
    ) {
        let availableSize = rect.size
        guard
            availableSize.width > 0,
            availableSize.height > 0,
            attributedText.length > 0
        else {
            return
        }

        let framesetter = CTFramesetterCreateWithAttributedString(
            attributedText as CFAttributedString
        )
        let textBounds = CGRect(origin: .zero, size: availableSize)

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            CGPath(rect: textBounds, transform: nil),
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func cgColor(for color: CanvasTextColor) -> CGColor {
        CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}
