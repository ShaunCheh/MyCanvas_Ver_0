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
    private static let isTraceLoggingEnabled = true
    private static let visibleRangeGapThreshold: CGFloat = 0.5

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
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(
                width: availableSize.width,
                height: CGFloat.greatestFiniteMagnitude
            ),
            nil
        )

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
        logVisibleRangeIfNeeded(
            frame: frame,
            attributedText: attributedText,
            availableSize: availableSize,
            suggestedSize: suggestedSize
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

    private func logVisibleRangeIfNeeded(
        frame: CTFrame,
        attributedText: NSAttributedString,
        availableSize: CGSize,
        suggestedSize: CGSize
    ) {
        guard Self.isTraceLoggingEnabled else {
            return
        }
        let visibleRange = CTFrameGetVisibleStringRange(frame)
        let totalLength = attributedText.length
        let hiddenLocation = visibleRange.location + visibleRange.length
        let hiddenLength = max(totalLength - hiddenLocation, 0)
        let heightGap = suggestedSize.height - availableSize.height
        guard hiddenLength > 0 || heightGap > Self.visibleRangeGapThreshold else {
            return
        }
        let plainText = attributedText.string as NSString
        let hiddenTail = hiddenLength > 0
            ? plainText.substring(with: NSRange(location: hiddenLocation, length: hiddenLength))
            : ""
        let visiblePreview = plainText.substring(
            with: NSRange(
                location: 0,
                length: min(visibleRange.length, totalLength)
            )
        )
        print(
            "[Canvas Markdown][Draw] " +
            "rect=\(Self.debugMarkdownSize(availableSize)) " +
            "suggested=\(Self.debugMarkdownSize(suggestedSize)) " +
            "heightGap=\(Self.debugMarkdownScalar(heightGap)) " +
            "visibleRange=\(visibleRange.location)+\(visibleRange.length) " +
            "totalLength=\(totalLength) " +
            "visibleTail=\"\(Self.debugMarkdownTail(visiblePreview))\" " +
            "hiddenTail=\"\(Self.debugMarkdownTail(hiddenTail))\""
        )
    }

    private static func debugMarkdownSize(_ size: CGSize) -> String {
        "\(debugMarkdownScalar(size.width))x\(debugMarkdownScalar(size.height))"
    }

    private static func debugMarkdownScalar(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private static func debugMarkdownTail(_ source: String, maxLength: Int = 120) -> String {
        debugMarkdownSingleLine(String(source.suffix(maxLength)))
    }

    private static func debugMarkdownSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
