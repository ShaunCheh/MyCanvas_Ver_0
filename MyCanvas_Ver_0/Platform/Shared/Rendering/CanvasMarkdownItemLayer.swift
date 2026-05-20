import CoreGraphics
import QuartzCore

// Markdown item layers own screen-space geometry while delegating bitmap
// generation to the nested content layer in logical item space.
final class CanvasMarkdownItemLayer: CALayer {
    private static let scrollbarVisibilityEpsilon: CGFloat = 0.5
    private static let preferredScrollbarThickness: CGFloat = 4
    private static let minimumScrollbarThickness: CGFloat = 2
    private static let preferredScrollbarInset: CGFloat = 3
    private static let scrollbarTrackGray: CGFloat = 0.42
    private static let scrollbarTrackAlpha: CGFloat = 0.16
    private static let scrollbarThumbAlpha: CGFloat = 0.55

    private struct ScrollbarMetrics: Equatable {
        let trackFrame: CGRect
        let thumbFrame: CGRect
    }

    let itemID: CanvasItemID
    let contentLayer: CanvasMarkdownContentLayer
    let scrollbarTrackLayer: CALayer
    let scrollbarThumbLayer: CALayer

    private var lastAppliedPosition: CGPoint
    private var lastAppliedLogicalSize: CGSize
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedRotationRadians: CGFloat
    private var lastAppliedCameraZoomScale: CGFloat
    private var lastAppliedScrollbarMetrics: ScrollbarMetrics?

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        contentLayer = CanvasMarkdownContentLayer(itemID: itemID)
        scrollbarTrackLayer = CALayer()
        scrollbarThumbLayer = CALayer()
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedLogicalSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedZIndex = .nan
        lastAppliedRotationRadians = .nan
        lastAppliedCameraZoomScale = .nan
        lastAppliedScrollbarMetrics = nil
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let itemLayer = layer as? CanvasMarkdownItemLayer {
            itemID = itemLayer.itemID
            contentLayer = CanvasMarkdownContentLayer(itemID: itemLayer.itemID)
            scrollbarTrackLayer = CALayer()
            scrollbarThumbLayer = CALayer()
            lastAppliedPosition = itemLayer.lastAppliedPosition
            lastAppliedLogicalSize = itemLayer.lastAppliedLogicalSize
            lastAppliedZIndex = itemLayer.lastAppliedZIndex
            lastAppliedRotationRadians = itemLayer.lastAppliedRotationRadians
            lastAppliedCameraZoomScale = itemLayer.lastAppliedCameraZoomScale
            lastAppliedScrollbarMetrics = itemLayer.lastAppliedScrollbarMetrics
        } else {
            itemID = UUID()
            contentLayer = CanvasMarkdownContentLayer(itemID: itemID)
            scrollbarTrackLayer = CALayer()
            scrollbarThumbLayer = CALayer()
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedLogicalSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedZIndex = .nan
            lastAppliedRotationRadians = .nan
            lastAppliedCameraZoomScale = .nan
            lastAppliedScrollbarMetrics = nil
        }

        super.init(layer: layer)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if lastAppliedLogicalSize != markdownPayload.logicalSize {
            bounds = CGRect(origin: .zero, size: markdownPayload.logicalSize)
            lastAppliedLogicalSize = markdownPayload.logicalSize
        }

        if lastAppliedPosition != item.screenCenter {
            position = item.screenCenter
            lastAppliedPosition = item.screenCenter
        }

        if
            lastAppliedRotationRadians != item.rotationRadians ||
            lastAppliedCameraZoomScale != markdownPayload.cameraZoomScale
        {
            transform = makeItemTransform(
                rotationRadians: item.rotationRadians,
                zoomScale: markdownPayload.cameraZoomScale
            )
            lastAppliedRotationRadians = item.rotationRadians
            lastAppliedCameraZoomScale = markdownPayload.cameraZoomScale
        }

        if lastAppliedZIndex != item.zIndex {
            zPosition = item.zIndex
            lastAppliedZIndex = item.zIndex
        }

        contentLayer.update(
            with: markdownPayload,
            contentsScale: contentsScale
        )
        applyScrollbar(
            logicalSize: markdownPayload.logicalSize,
            contentSize: contentLayer.bounds.size,
            scrollOffsetY: max(-contentLayer.position.y, 0)
        )

        CATransaction.commit()
    }

    private func configureLayer() {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
        if contentLayer.superlayer !== self {
            addSublayer(contentLayer)
        }
        configureScrollbarLayer(scrollbarTrackLayer)
        configureScrollbarLayer(scrollbarThumbLayer)
        scrollbarTrackLayer.backgroundColor = CGColor(
            gray: Self.scrollbarTrackGray,
            alpha: Self.scrollbarTrackAlpha
        )
        scrollbarThumbLayer.backgroundColor = CGColor(
            gray: Self.scrollbarTrackGray,
            alpha: Self.scrollbarThumbAlpha
        )
        if scrollbarTrackLayer.superlayer !== self {
            addSublayer(scrollbarTrackLayer)
        }
        if scrollbarThumbLayer.superlayer !== self {
            addSublayer(scrollbarThumbLayer)
        }
    }

    private func makeItemTransform(
        rotationRadians: CGFloat,
        zoomScale: CGFloat
    ) -> CATransform3D {
        let resolvedZoomScale =
            zoomScale.isFinite && zoomScale > 0 ? zoomScale : 1
        let rotationTransform = CATransform3DMakeRotation(rotationRadians, 0, 0, 1)
        return CATransform3DScale(
            rotationTransform,
            resolvedZoomScale,
            resolvedZoomScale,
            1
        )
    }

    private func configureScrollbarLayer(_ layer: CALayer) {
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.isHidden = true
        layer.masksToBounds = true
    }

    private func applyScrollbar(
        logicalSize: CGSize,
        contentSize: CGSize,
        scrollOffsetY: CGFloat
    ) {
        guard let metrics = resolvedScrollbarMetrics(
            logicalSize: logicalSize,
            contentSize: contentSize,
            scrollOffsetY: scrollOffsetY
        ) else {
            guard lastAppliedScrollbarMetrics != nil else {
                return
            }
            scrollbarTrackLayer.isHidden = true
            scrollbarThumbLayer.isHidden = true
            lastAppliedScrollbarMetrics = nil
            return
        }

        if lastAppliedScrollbarMetrics != metrics {
            scrollbarTrackLayer.frame = metrics.trackFrame
            scrollbarTrackLayer.cornerRadius = metrics.trackFrame.width / 2
            scrollbarThumbLayer.frame = metrics.thumbFrame
            scrollbarThumbLayer.cornerRadius = metrics.thumbFrame.width / 2
            lastAppliedScrollbarMetrics = metrics
        }
        scrollbarTrackLayer.isHidden = false
        scrollbarThumbLayer.isHidden = false
    }

    private func resolvedScrollbarMetrics(
        logicalSize: CGSize,
        contentSize: CGSize,
        scrollOffsetY: CGFloat
    ) -> ScrollbarMetrics? {
        guard
            logicalSize.width > 0,
            logicalSize.height > 0,
            contentSize.height - logicalSize.height > Self.scrollbarVisibilityEpsilon
        else {
            return nil
        }

        let thickness = resolvedScrollbarThickness(forLogicalWidth: logicalSize.width)
        let horizontalInset = min(
            Self.preferredScrollbarInset,
            max((logicalSize.width - thickness) / 2, 0)
        )
        let verticalInset = min(
            Self.preferredScrollbarInset,
            max((logicalSize.height - thickness) / 2, 0)
        )
        let trackHeight = logicalSize.height - (verticalInset * 2)
        guard trackHeight > 0 else {
            return nil
        }

        let maxScrollOffsetY = max(contentSize.height - logicalSize.height, 0)
        guard maxScrollOffsetY > Self.scrollbarVisibilityEpsilon else {
            return nil
        }
        let minimumThumbHeight = min(trackHeight, thickness * 2)
        let proportionalThumbHeight = trackHeight * (logicalSize.height / contentSize.height)
        let thumbHeight = min(
            max(proportionalThumbHeight, minimumThumbHeight),
            trackHeight
        )
        let thumbTravel = max(trackHeight - thumbHeight, 0)
        let progress = min(max(scrollOffsetY / maxScrollOffsetY, 0), 1)
        let trackX = max(logicalSize.width - horizontalInset - thickness, 0)
        let trackY = verticalInset
        let thumbY = trackY + (thumbTravel * progress)
        return ScrollbarMetrics(
            trackFrame: CGRect(
                x: trackX,
                y: trackY,
                width: thickness,
                height: trackHeight
            ),
            thumbFrame: CGRect(
                x: trackX,
                y: thumbY,
                width: thickness,
                height: thumbHeight
            )
        )
    }

    private func resolvedScrollbarThickness(
        forLogicalWidth logicalWidth: CGFloat
    ) -> CGFloat {
        let minimumThickness = min(Self.minimumScrollbarThickness, logicalWidth)
        let preferredThickness = min(
            Self.preferredScrollbarThickness,
            logicalWidth * 0.08
        )
        return max(minimumThickness, preferredThickness)
    }
}
