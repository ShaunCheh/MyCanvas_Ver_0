import CoreGraphics
import QuartzCore

// Markdown item layers own screen-space geometry while delegating bitmap
// generation to the nested content layer in logical item space.
final class CanvasMarkdownItemLayer: CALayer {
    let itemID: CanvasItemID
    let contentLayer: CanvasMarkdownContentLayer

    private var lastAppliedPosition: CGPoint
    private var lastAppliedLogicalSize: CGSize
    private var lastAppliedZIndex: CGFloat
    private var lastAppliedRotationRadians: CGFloat
    private var lastAppliedCameraZoomScale: CGFloat

    init(itemID: CanvasItemID) {
        self.itemID = itemID
        contentLayer = CanvasMarkdownContentLayer(itemID: itemID)
        lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        lastAppliedLogicalSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        lastAppliedZIndex = .nan
        lastAppliedRotationRadians = .nan
        lastAppliedCameraZoomScale = .nan
        super.init()
        configureLayer()
    }

    override init(layer: Any) {
        if let itemLayer = layer as? CanvasMarkdownItemLayer {
            itemID = itemLayer.itemID
            contentLayer = CanvasMarkdownContentLayer(itemID: itemLayer.itemID)
            lastAppliedPosition = itemLayer.lastAppliedPosition
            lastAppliedLogicalSize = itemLayer.lastAppliedLogicalSize
            lastAppliedZIndex = itemLayer.lastAppliedZIndex
            lastAppliedRotationRadians = itemLayer.lastAppliedRotationRadians
            lastAppliedCameraZoomScale = itemLayer.lastAppliedCameraZoomScale
        } else {
            itemID = UUID()
            contentLayer = CanvasMarkdownContentLayer(itemID: itemID)
            lastAppliedPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
            lastAppliedLogicalSize = CGSize(width: CGFloat.nan, height: CGFloat.nan)
            lastAppliedZIndex = .nan
            lastAppliedRotationRadians = .nan
            lastAppliedCameraZoomScale = .nan
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

        CATransaction.commit()
    }

    private func configureLayer() {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
        if contentLayer.superlayer !== self {
            addSublayer(contentLayer)
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
}
