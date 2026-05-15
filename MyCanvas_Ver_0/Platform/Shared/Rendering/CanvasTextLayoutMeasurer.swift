import CoreGraphics
import CoreText
import Foundation

struct CanvasTextLayoutMetrics: Hashable, Sendable {
    var minimumSize: CGSize
    var horizontalInset: CGFloat
    var verticalInset: CGFloat

    // These rules define the future content-driven text item box without
    // forcing later phases to rediscover padding/minimums in multiple surfaces.
    static let contentDrivenItem = CanvasTextLayoutMetrics(
        minimumSize: CGSize(width: 24, height: 20),
        horizontalInset: 12,
        verticalInset: 10
    )

    // Tight content measurement describes the raw glyph bounds surfaces can use
    // when they need content-only sizing without extra padding/minimum rules.
    static let tightContent = CanvasTextLayoutMetrics(
        minimumSize: .zero,
        horizontalInset: 0,
        verticalInset: 0
    )
}

enum CanvasTextLayoutMeasurer {
    // Main canvas rendering, thumbnails, and future content-driven item sizing
    // should all measure text through the same helper so geometry stays in sync.
    static func renderFontSize(
        for style: CanvasTextStyle,
        scale: CGFloat = 1
    ) -> CGFloat {
        max(style.fontSize * scale, 1)
    }

    static func intrinsicContentSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat = 1
    ) -> CGSize {
        measuredSize(
            for: text,
            style: style,
            scale: scale,
            metrics: .tightContent
        )
    }

    static func intrinsicItemSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat = 1,
        metrics: CanvasTextLayoutMetrics = .contentDrivenItem
    ) -> CGSize {
        measuredSize(
            for: text,
            style: style,
            scale: scale,
            metrics: metrics
        )
    }

    private static func measuredSize(
        for text: String,
        style: CanvasTextStyle,
        scale: CGFloat,
        metrics: CanvasTextLayoutMetrics
    ) -> CGSize {
        let baseFontSize = renderFontSize(
            for: style,
            scale: scale
        )
        let font = textFont(
            named: style.fontName,
            size: baseFontSize
        )
        let attributedText = NSAttributedString(
            string: text,
            attributes: textAttributes(
                font: font,
                paragraphStyle: textParagraphStyle()
            )
        )
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributedText as CFAttributedString
        )
        let measuredSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            nil
        )
        let paddedSize = CGSize(
            width: ceil(max(measuredSize.width, 0)) + metrics.horizontalInset * 2,
            height: ceil(max(measuredSize.height, 0)) + metrics.verticalInset * 2
        )
        return CGSize(
            width: max(paddedSize.width, metrics.minimumSize.width),
            height: max(paddedSize.height, metrics.minimumSize.height)
        )
    }

    private static func textParagraphStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        var lineBreakMode = CTLineBreakMode.byClipping
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakModePointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineBreakMode,
                        valueSize: MemoryLayout<CTLineBreakMode>.size,
                        value: lineBreakModePointer
                    )
                ]
                return settings.withUnsafeBufferPointer { buffer in
                    CTParagraphStyleCreate(buffer.baseAddress!, buffer.count)
                }
            }
        }
    }

    private static func textAttributes(
        font: CTFont,
        paragraphStyle: CTParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(
                rawValue: kCTParagraphStyleAttributeName as String
            ): paragraphStyle
        ]
    }

    private static func textFont(
        named fontName: String,
        size: CGFloat
    ) -> CTFont {
        let resolvedSize = max(size, 1)
        guard fontName.isEmpty == false, fontName != "System" else {
            return CTFontCreateUIFontForLanguage(
                .system,
                resolvedSize,
                nil
            ) ?? CTFontCreateWithName(
                "Helvetica" as CFString,
                resolvedSize,
                nil
            )
        }

        return CTFontCreateWithName(
            fontName as CFString,
            resolvedSize,
            nil
        )
    }
}
