import CoreGraphics
import QuartzCore

// Markdown content renders into a bitmap in logical item space. Camera zoom only
// influences raster density, never the semantic layout width or font sizing.
final class CanvasMarkdownContentLayer: CALayer {
    let itemID: CanvasItemID

    private let bitmapRenderer: CanvasMarkdownBitmapRenderer
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedMarkdownSource: String
    private var lastAppliedStyle: CanvasTextStyle?
    private var lastAppliedLogicalWidth: CGFloat
    private var lastAppliedRasterScale: CGFloat
    private var lastAppliedLayoutSize: CGSize
    private var cachedLayout: CanvasMarkdownLayoutResult?

    init(
        itemID: CanvasItemID,
        bitmapRenderer: CanvasMarkdownBitmapRenderer = CanvasMarkdownBitmapRenderer()
    ) {
        self.itemID = itemID
        self.bitmapRenderer = bitmapRenderer
        lastAppliedContentsScale = .nan
        lastAppliedMarkdownSource = ""
        lastAppliedStyle = nil
        lastAppliedLogicalWidth = .nan
        lastAppliedRasterScale = .nan
        lastAppliedLayoutSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        cachedLayout = nil
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let contentLayer = layer as? CanvasMarkdownContentLayer {
            itemID = contentLayer.itemID
            bitmapRenderer = contentLayer.bitmapRenderer
            lastAppliedContentsScale = contentLayer.lastAppliedContentsScale
            lastAppliedMarkdownSource = contentLayer.lastAppliedMarkdownSource
            lastAppliedStyle = contentLayer.lastAppliedStyle
            lastAppliedLogicalWidth = contentLayer.lastAppliedLogicalWidth
            lastAppliedRasterScale = contentLayer.lastAppliedRasterScale
            lastAppliedLayoutSize = contentLayer.lastAppliedLayoutSize
            cachedLayout = contentLayer.cachedLayout
        } else {
            itemID = UUID()
            bitmapRenderer = CanvasMarkdownBitmapRenderer()
            lastAppliedContentsScale = .nan
            lastAppliedMarkdownSource = ""
            lastAppliedStyle = nil
            lastAppliedLogicalWidth = .nan
            lastAppliedRasterScale = .nan
            lastAppliedLayoutSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            cachedLayout = nil
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        with markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedContentsScale != contentsScale {
            self.contentsScale = contentsScale
            lastAppliedContentsScale = contentsScale
        }

        let needsLayoutRefresh = shouldRefreshLayout(
            markdownPayload: markdownPayload
        ) || cachedLayout == nil
        if needsLayoutRefresh {
            cachedLayout = makeLayout(
                from: markdownPayload
            )
            lastAppliedMarkdownSource = markdownPayload.markdownSource
            lastAppliedStyle = markdownPayload.style
            lastAppliedLogicalWidth = markdownPayload.logicalSize.width
        }

        if let cachedLayout {
            applyLayoutGeometry(cachedLayout)
            let rasterScale = resolvedRasterScale(
                markdownPayload: markdownPayload,
                contentsScale: contentsScale
            )
            if needsLayoutRefresh || lastAppliedRasterScale != rasterScale || contents == nil {
                contents = bitmapRenderer.render(
                    layout: cachedLayout,
                    rasterScale: rasterScale
                )
                lastAppliedRasterScale = rasterScale
            }
        } else {
            contents = nil
            lastAppliedRasterScale = .nan
        }

        CATransaction.commit()
    }

    private func configureLayer() {
        anchorPoint = .zero
        position = .zero
        contentsGravity = .resize
        masksToBounds = false
        isOpaque = false
    }

    private func shouldRefreshLayout(
        markdownPayload: CanvasMarkdownRenderPayload
    ) -> Bool {
        lastAppliedMarkdownSource != markdownPayload.markdownSource ||
        lastAppliedStyle != markdownPayload.style ||
        lastAppliedLogicalWidth != markdownPayload.logicalSize.width
    }

    private func makeLayout(
        from markdownPayload: CanvasMarkdownRenderPayload
    ) -> CanvasMarkdownLayoutResult {
        CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: markdownPayload.markdownSource,
            style: markdownPayload.style,
            maxLayoutWidth: markdownPayload.logicalSize.width,
            scale: 1,
            includeCompatibilityCodeBlockBackgrounds: false
        )
    }

    private func applyLayoutGeometry(
        _ layout: CanvasMarkdownLayoutResult
    ) {
        guard lastAppliedLayoutSize != layout.contentSize else {
            return
        }

        bounds = CGRect(origin: .zero, size: layout.contentSize)
        lastAppliedLayoutSize = layout.contentSize
    }

    private func resolvedRasterScale(
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) -> CGFloat {
        let resolvedContentsScale =
            contentsScale.isFinite && contentsScale > 0 ? contentsScale : 1
        let resolvedZoomScale =
            markdownPayload.cameraZoomScale.isFinite && markdownPayload.cameraZoomScale > 0
            ? markdownPayload.cameraZoomScale
            : 1
        return max(resolvedContentsScale * resolvedZoomScale, 1)
    }
}
