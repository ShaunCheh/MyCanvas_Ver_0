import CoreGraphics
import Foundation
import QuartzCore

// Markdown content renders into a bitmap in logical item space. Camera zoom only
// influences raster density, never the semantic layout width or font sizing.
final class CanvasMarkdownContentLayer: CALayer {
    typealias LayoutProvider = (CanvasMarkdownRenderPayload) -> CanvasMarkdownLayoutResult

    // Discrete upward buckets keep zoom behavior predictable: pinch updates can
    // reuse the current bitmap until the requested density crosses the next
    // threshold, at which point we reraster once without relaying out text.
    private static let rasterScaleBuckets: [CGFloat] = [
        1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24
    ]
    private static let isTraceLoggingEnabled = true
    private static let layoutMismatchThreshold: CGFloat = 0.5

    private struct LayoutCacheKey: Hashable {
        let markdownSource: String
        let fontName: String
        let fontSize: Double
        let colorRed: Double
        let colorGreen: Double
        let colorBlue: Double
        let colorAlpha: Double
        let logicalWidth: Double

        init(markdownPayload: CanvasMarkdownRenderPayload) {
            markdownSource = markdownPayload.markdownSource
            fontName = markdownPayload.style.fontName
            fontSize = Double(markdownPayload.style.fontSize)
            colorRed = Double(markdownPayload.style.color.red)
            colorGreen = Double(markdownPayload.style.color.green)
            colorBlue = Double(markdownPayload.style.color.blue)
            colorAlpha = Double(markdownPayload.style.color.alpha)
            logicalWidth = Double(markdownPayload.logicalSize.width)
        }
    }

    private struct RasterScaleBucket: Hashable {
        let scale: Double

        var cgFloatScale: CGFloat {
            CGFloat(scale)
        }
    }

    private struct BitmapCacheKey: Hashable {
        let layoutKey: LayoutCacheKey
        let rasterScaleBucket: RasterScaleBucket
    }

    let itemID: CanvasItemID

    private let bitmapRenderer: any CanvasMarkdownBitmapRendering
    private let layoutProvider: LayoutProvider
    private var lastAppliedContentsScale: CGFloat
    private var lastAppliedLayoutSize: CGSize
    private var lastAppliedScrollOffsetY: CGFloat
    private var activeLayoutKey: LayoutCacheKey?
    private var activeBitmapKey: BitmapCacheKey?
    private var activeLayout: CanvasMarkdownLayoutResult?
    private var layoutCache: [LayoutCacheKey: CanvasMarkdownLayoutResult]
    private var bitmapCache: [BitmapCacheKey: CGImage]

    init(
        itemID: CanvasItemID,
        bitmapRenderer: any CanvasMarkdownBitmapRendering = CanvasMarkdownBitmapRenderer(),
        layoutProvider: @escaping LayoutProvider = CanvasMarkdownContentLayer.defaultLayout(for:)
    ) {
        self.itemID = itemID
        self.bitmapRenderer = bitmapRenderer
        self.layoutProvider = layoutProvider
        lastAppliedContentsScale = .nan
        lastAppliedLayoutSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedScrollOffsetY = .nan
        activeLayoutKey = nil
        activeBitmapKey = nil
        activeLayout = nil
        layoutCache = [:]
        bitmapCache = [:]
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let contentLayer = layer as? CanvasMarkdownContentLayer {
            itemID = contentLayer.itemID
            bitmapRenderer = contentLayer.bitmapRenderer
            layoutProvider = contentLayer.layoutProvider
            lastAppliedContentsScale = contentLayer.lastAppliedContentsScale
            lastAppliedLayoutSize = contentLayer.lastAppliedLayoutSize
            lastAppliedScrollOffsetY = contentLayer.lastAppliedScrollOffsetY
            activeLayoutKey = contentLayer.activeLayoutKey
            activeBitmapKey = contentLayer.activeBitmapKey
            activeLayout = contentLayer.activeLayout
            layoutCache = contentLayer.layoutCache
            bitmapCache = contentLayer.bitmapCache
        } else {
            itemID = UUID()
            bitmapRenderer = CanvasMarkdownBitmapRenderer()
            layoutProvider = CanvasMarkdownContentLayer.defaultLayout(for:)
            lastAppliedContentsScale = .nan
            lastAppliedLayoutSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedScrollOffsetY = .nan
            activeLayoutKey = nil
            activeBitmapKey = nil
            activeLayout = nil
            layoutCache = [:]
            bitmapCache = [:]
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var currentLayout: CanvasMarkdownLayoutResult? {
        activeLayout
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

        let layoutKey = LayoutCacheKey(markdownPayload: markdownPayload)
        let layout = resolvedLayout(
            for: markdownPayload,
            layoutKey: layoutKey
        )
        applyLayoutGeometry(layout)
        applyScrollOffset(markdownPayload: markdownPayload, layout: layout)

        let rasterScaleBucket = resolvedRasterScaleBucket(
            markdownPayload: markdownPayload,
            contentsScale: contentsScale
        )
        logLayoutMismatchIfNeeded(
            markdownPayload: markdownPayload,
            layout: layout,
            contentsScale: contentsScale,
            rasterScaleBucket: rasterScaleBucket
        )
        applyBitmapIfNeeded(
            for: layout,
            layoutKey: layoutKey,
            rasterScaleBucket: rasterScaleBucket
        )

        CATransaction.commit()
    }

    nonisolated private static func defaultLayout(
        for markdownPayload: CanvasMarkdownRenderPayload
    ) -> CanvasMarkdownLayoutResult {
        CanvasMarkdownLayoutMeasurer.layout(
            markdownSource: markdownPayload.markdownSource,
            style: markdownPayload.style,
            maxLayoutWidth: markdownPayload.logicalSize.width,
            scale: 1,
            includeCompatibilityCodeBlockBackgrounds: false
        )
    }

    private func resolvedLayout(
        for markdownPayload: CanvasMarkdownRenderPayload,
        layoutKey: LayoutCacheKey
    ) -> CanvasMarkdownLayoutResult {
        if activeLayoutKey == layoutKey, let activeLayout {
            return activeLayout
        }

        if let cachedLayout = layoutCache[layoutKey] {
            activeLayoutKey = layoutKey
            activeLayout = cachedLayout
            return cachedLayout
        }

        let resolvedLayout = layoutProvider(markdownPayload)
        layoutCache[layoutKey] = resolvedLayout
        activeLayoutKey = layoutKey
        activeLayout = resolvedLayout
        return resolvedLayout
    }

    private func applyBitmapIfNeeded(
        for layout: CanvasMarkdownLayoutResult,
        layoutKey: LayoutCacheKey,
        rasterScaleBucket: RasterScaleBucket
    ) {
        let bitmapKey = BitmapCacheKey(
            layoutKey: layoutKey,
            rasterScaleBucket: rasterScaleBucket
        )
        guard activeBitmapKey != bitmapKey || contents == nil else {
            return
        }

        if let cachedImage = bitmapCache[bitmapKey] {
            contents = cachedImage
            activeBitmapKey = bitmapKey
            return
        }

        let renderedImage = bitmapRenderer.render(
            layout: layout,
            rasterScale: rasterScaleBucket.cgFloatScale
        )
        contents = renderedImage
        if let renderedImage {
            bitmapCache[bitmapKey] = renderedImage
            activeBitmapKey = bitmapKey
        } else {
            activeBitmapKey = nil
        }
    }

    private func configureLayer() {
        anchorPoint = .zero
        position = .zero
        contentsGravity = .resize
        masksToBounds = false
        isOpaque = false
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

    private func applyScrollOffset(
        markdownPayload: CanvasMarkdownRenderPayload,
        layout: CanvasMarkdownLayoutResult
    ) {
        let maxScrollOffsetY = max(
            layout.contentSize.height - markdownPayload.logicalSize.height,
            0
        )
        let resolvedScrollOffsetY = min(
            max(markdownPayload.scrollOffsetY, 0),
            maxScrollOffsetY
        )
        guard lastAppliedScrollOffsetY != resolvedScrollOffsetY else {
            return
        }
        position = CGPoint(x: 0, y: -resolvedScrollOffsetY)
        lastAppliedScrollOffsetY = resolvedScrollOffsetY
    }

    private func resolvedRasterScaleBucket(
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) -> RasterScaleBucket {
        let resolvedContentsScale =
            contentsScale.isFinite && contentsScale > 0 ? contentsScale : 1
        let resolvedZoomScale =
            markdownPayload.cameraZoomScale.isFinite && markdownPayload.cameraZoomScale > 0
            ? markdownPayload.cameraZoomScale
            : 1
        let requestedRasterScale = max(
            resolvedContentsScale * resolvedZoomScale,
            1
        )
        let bucketScale =
            Self.rasterScaleBuckets.first(where: { requestedRasterScale <= $0 })
            ?? max(
                ceil(requestedRasterScale),
                Self.rasterScaleBuckets.last ?? 1
            )
        return RasterScaleBucket(scale: Double(bucketScale))
    }

    private func logLayoutMismatchIfNeeded(
        markdownPayload: CanvasMarkdownRenderPayload,
        layout: CanvasMarkdownLayoutResult,
        contentsScale: CGFloat,
        rasterScaleBucket: RasterScaleBucket
    ) {
        guard Self.isTraceLoggingEnabled else {
            return
        }
        let widthDelta = layout.contentSize.width - markdownPayload.logicalSize.width
        let heightDelta = layout.contentSize.height - markdownPayload.logicalSize.height
        guard
            abs(widthDelta) > Self.layoutMismatchThreshold
        else {
            return
        }
        print(
            "[Canvas Markdown][ClipRisk] " +
            "itemID=\(itemID.uuidString) " +
            "payloadSize=\(Self.debugMarkdownSize(markdownPayload.logicalSize)) " +
            "layoutSize=\(Self.debugMarkdownSize(layout.contentSize)) " +
            "delta=\(Self.debugMarkdownSize(CGSize(width: widthDelta, height: heightDelta))) " +
            "zoom=\(Self.debugMarkdownScalar(markdownPayload.cameraZoomScale)) " +
            "contentsScale=\(Self.debugMarkdownScalar(contentsScale)) " +
            "rasterBucket=\(Self.debugMarkdownScalar(rasterScaleBucket.cgFloatScale)) " +
            "lastLine=\"\(Self.debugMarkdownLastNonEmptyLine(in: markdownPayload.markdownSource))\" " +
            "tail=\"\(Self.debugMarkdownTail(markdownPayload.markdownSource))\""
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

    private static func debugMarkdownLastNonEmptyLine(in source: String) -> String {
        let line = source
            .components(separatedBy: .newlines)
            .reversed()
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            ?? ""
        return debugMarkdownSingleLine(line)
    }

    private static func debugMarkdownSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
