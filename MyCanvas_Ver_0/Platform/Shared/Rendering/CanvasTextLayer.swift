import CoreGraphics
import QuartzCore

#if os(macOS)
import AppKit
private typealias CanvasPlatformColor = NSColor
private typealias CanvasPlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias CanvasPlatformColor = UIColor
private typealias CanvasPlatformFont = UIFont
#endif

// Text layers keep glyph layout platform-local so shared render snapshots only
// need to describe geometry, style, and zoom information.
final class CanvasTextLayer: CATextLayer {
    let itemID: CanvasItemID
    private var lastAppliedPosition: CGPoint
    private var lastAppliedBoundsSize: CGSize
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedRotationRadians: CGFloat
    private var lastAppliedText: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedZoomScale: CGFloat
    private var lastAppliedLayoutBoundsSize: CGSize

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedZIndex = .nan
        lastAppliedContentsScale = .nan
        lastAppliedRotationRadians = .nan
        lastAppliedText = ""
        lastAppliedStyle = nil
        lastAppliedZoomScale = .nan
        lastAppliedLayoutBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let textLayer = layer as? CanvasTextLayer {
            itemID = textLayer.itemID
            lastAppliedPosition = textLayer.lastAppliedPosition
            lastAppliedBoundsSize = textLayer.lastAppliedBoundsSize
            lastAppliedZIndex = textLayer.lastAppliedZIndex
            lastAppliedContentsScale = textLayer.lastAppliedContentsScale
            lastAppliedRotationRadians = textLayer.lastAppliedRotationRadians
            lastAppliedText = textLayer.lastAppliedText
            lastAppliedStyle = textLayer.lastAppliedStyle
            lastAppliedZoomScale = textLayer.lastAppliedZoomScale
            lastAppliedLayoutBoundsSize = textLayer.lastAppliedLayoutBoundsSize
        } else {
            itemID = UUID()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedZIndex = .nan
            lastAppliedContentsScale = .nan
            lastAppliedRotationRadians = .nan
            lastAppliedText = ""
            lastAppliedStyle = nil
            lastAppliedZoomScale = .nan
            lastAppliedLayoutBoundsSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        with item: CanvasRenderItem,
        textPayload: CanvasTextRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedBoundsSize != item.screenBoundsSize {
            bounds = CGRect(origin: .zero, size: item.screenBoundsSize)
            lastAppliedBoundsSize = item.screenBoundsSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if lastAppliedRotationRadians != item.rotationRadians {
            transform = CATransform3DMakeRotation(item.rotationRadians, 0, 0, 1)
            lastAppliedRotationRadians = item.rotationRadians
        }

        if lastAppliedZIndex != item.zIndex {
            zPosition = item.zIndex
            lastAppliedZIndex = item.zIndex
        }

        if lastAppliedContentsScale != contentsScale {
            self.contentsScale = contentsScale
            lastAppliedContentsScale = contentsScale
        }

        if shouldRefreshAttributedText(
            textPayload: textPayload,
            layoutBoundsSize: item.screenBoundsSize
        ) {
            string = makeAttributedText(
                from: textPayload,
                availableSize: item.screenBoundsSize
            )
            lastAppliedText = textPayload.text
            lastAppliedStyle = textPayload.style
            lastAppliedZoomScale = textPayload.zoomScale
            lastAppliedLayoutBoundsSize = item.screenBoundsSize
        }

        CATransaction.commit()
    }

    private func configureLayer() {
        alignmentMode = .center
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        isWrapped = true
        truncationMode = .none
        masksToBounds = false
    }

    private func shouldRefreshAttributedText(
        textPayload: CanvasTextRenderPayload,
        layoutBoundsSize: CGSize
    ) -> Bool {
        lastAppliedText != textPayload.text ||
        lastAppliedStyle != textPayload.style ||
        lastAppliedZoomScale != textPayload.zoomScale ||
        lastAppliedLayoutBoundsSize != layoutBoundsSize
    }

    private func makeAttributedText(
        from textPayload: CanvasTextRenderPayload,
        availableSize: CGSize
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping

        let font = fittedFont(
            for: textPayload,
            availableSize: availableSize
        )
        let textColor = platformColor(for: textPayload.style.color)

        return NSAttributedString(
            string: textPayload.text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func fittedFont(
        for textPayload: CanvasTextRenderPayload,
        availableSize: CGSize
    ) -> CanvasPlatformFont {
        let baseFontSize = max(textPayload.style.fontSize * textPayload.zoomScale, 1)
        let baseFont = platformFont(
            named: textPayload.style.fontName,
            size: baseFontSize
        )
        let intrinsicSize = CanvasTextLayoutMeasurer.intrinsicContentSize(
            for: textPayload.text,
            style: textPayload.style,
            scale: textPayload.zoomScale
        )
        guard
            availableSize.width > 0,
            availableSize.height > 0,
            intrinsicSize.width > 0,
            intrinsicSize.height > 0
        else {
            return baseFont
        }

        let scale = min(
            availableSize.width / intrinsicSize.width,
            availableSize.height / intrinsicSize.height
        )
        guard scale.isFinite, scale > 0 else {
            return baseFont
        }

        return platformFont(
            named: textPayload.style.fontName,
            size: max(baseFontSize * scale, 1)
        )
    }

    private func platformFont(
        named fontName: String,
        size: CGFloat
    ) -> CanvasPlatformFont {
        let resolvedSize = max(size, 1)
        if fontName == "System" {
            return systemFont(ofSize: resolvedSize)
        }

        return namedPlatformFont(fontName, size: resolvedSize) ??
            systemFont(ofSize: resolvedSize)
    }

    private func platformColor(
        for color: CanvasTextColor
    ) -> CanvasPlatformColor {
        CanvasPlatformColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}

private func namedPlatformFont(
    _ fontName: String,
    size: CGFloat
) -> CanvasPlatformFont? {
    #if os(macOS)
    CanvasPlatformFont(name: fontName, size: size)
    #else
    CanvasPlatformFont(name: fontName, size: size)
    #endif
}

private func systemFont(ofSize size: CGFloat) -> CanvasPlatformFont {
    #if os(macOS)
    CanvasPlatformFont.systemFont(ofSize: size)
    #else
    CanvasPlatformFont.systemFont(ofSize: size)
    #endif
}
